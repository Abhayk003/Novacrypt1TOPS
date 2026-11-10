//==============================================================================
// proc_mem_model.sv
//
// Simple word-addressed sparse memory, shared by the instruction and data
// AXI responders. Loaded once at build time from a $readmemh image (the
// same program image the golden Python ISS ran over -- see
// golden/gen_golden.py), so both the RTL and the reference model start
// from identical memory content.
//==============================================================================
class proc_mem_model extends uvm_object;
  `uvm_object_utils(proc_mem_model)

  // word-indexed (byte_addr[31:2]) sparse storage
  bit [31:0] mem[bit [29:0]];

  function new(string name = "proc_mem_model");
    super.new(name);
  endfunction

  function void load_readmemh(string path);
    // Deliberately NOT using $readmemh directly on an associative array:
    // whether that's portable across simulators is genuinely unclear (the
    // LRM's $readmemh text is written around unpacked arrays; associative-
    // array support is a documented VCS extension in some versions but not
    // something to just assume works identically everywhere). Parsing the
    // file by hand removes that dependency completely -- this is plain
    // file I/O + string parsing, which behaves identically everywhere.
    //
    // File format (see golden/gen_golden.py:write_readmemh_regions):
    //   "@<hex word index>"   -- repositions the running word index
    //   "<hex 32-bit word>"   -- one word, stored at the current index,
    //                            index then increments by 1
    int fd;
    string line;
    bit [29:0] widx;
    bit [31:0] word;
    int scan_ok;
    if (path == "") return;
    fd = $fopen(path, "r");
    if (fd == 0) begin
      `uvm_error("PROC_MEM_MODEL", $sformatf("could not open %s for read", path))
      return;
    end
    widx = 0;
    while (!$feof(fd)) begin
      if ($fgets(line, fd) == 0) break;
      line = strip_ws(line);
      if (line.len() == 0) continue;
      if (line[0] == "@") begin
        scan_ok = $sscanf(line.substr(1, line.len()-1), "%h", widx);
        if (scan_ok != 1)
          `uvm_error("PROC_MEM_MODEL", $sformatf("bad '@' marker line in %s: %s", path, line))
      end else begin
        scan_ok = $sscanf(line, "%h", word);
        if (scan_ok != 1) begin
          `uvm_error("PROC_MEM_MODEL", $sformatf("unparseable line in %s: %s", path, line))
        end else begin
          mem[widx] = word;
          widx++;
        end
      end
    end
    $fclose(fd);
  endfunction

  // Trim trailing \n / \r / spaces $fgets leaves on the line, and any
  // leading whitespace -- keeps the parser above simple string-compare.
  local function string strip_ws(string s);
    int lo, hi;
    lo = 0;
    hi = s.len() - 1;
    while (lo <= hi && (s[lo] == " " || s[lo] == "\t")) lo++;
    while (hi >= lo && (s[hi] == " " || s[hi] == "\t" || s[hi] == "\n" || s[hi] == "\r")) hi--;
    if (hi < lo) return "";
    return s.substr(lo, hi);
  endfunction

  function bit [31:0] read_word(bit [31:0] byte_addr);
    bit [29:0] widx = byte_addr[31:2];
    if (mem.exists(widx)) return mem[widx];
    return 32'h0000_0000;
  endfunction

  function void write_word(bit [31:0] byte_addr, bit [31:0] data, bit [3:0] strb);
    bit [29:0] widx = byte_addr[31:2];
    bit [31:0] cur = read_word(byte_addr);
    bit [31:0] merged;
    merged[7:0]   = strb[0] ? data[7:0]   : cur[7:0];
    merged[15:8]  = strb[1] ? data[15:8]  : cur[15:8];
    merged[23:16] = strb[2] ? data[23:16] : cur[23:16];
    merged[31:24] = strb[3] ? data[31:24] : cur[31:24];
    mem[widx] = merged;
  endfunction

  // Dump a [lo,hi] byte-address range as a $readmemh-compatible file,
  // one word per line, address-order -- used to diff against the
  // golden model's own final-DMEM dump.
  function void dump_range(string path, bit [31:0] lo, bit [31:0] hi);
    int fd = $fopen(path, "w");
    bit [31:0] a;
    if (fd == 0) begin
      `uvm_error("PROC_MEM_MODEL", $sformatf("could not open %s for write", path))
      return;
    end
    for (a = lo; a <= hi; a += 4) begin
      $fwrite(fd, "%08h\n", read_word(a));
    end
    $fclose(fd);
  endfunction

endclass : proc_mem_model
