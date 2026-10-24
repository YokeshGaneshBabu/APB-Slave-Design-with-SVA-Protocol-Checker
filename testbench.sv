`timescale 1ns/1ps

module tb_apb;

    localparam ADDR_WIDTH = 8;
    localparam DATA_WIDTH = 32;

    logic PCLK;
    logic PRESETn;

    initial PCLK = 0;
    always #5 PCLK = ~PCLK;

    apb_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) apb (
        .PCLK    (PCLK),
        .PRESETn (PRESETn)
    );

    apb_slave #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .apb (apb.slave)
    );

    task automatic apb_idle();
        apb.PSEL    = 0;
        apb.PENABLE = 0;
        apb.PADDR   = '0;
        apb.PWRITE  = 0;
        apb.PWDATA  = '0;
    endtask


    task automatic apb_write(
        input [ADDR_WIDTH-1:0] addr,
        input [DATA_WIDTH-1:0] data
    );

        @(posedge PCLK);

        apb.PADDR   = addr;
        apb.PWRITE  = 1'b1;
        apb.PWDATA  = data;
        apb.PSEL    = 1'b1;
        apb.PENABLE = 1'b0;

        @(posedge PCLK);

        apb.PENABLE = 1'b1;

        do @(posedge PCLK);
        while (!apb.PREADY);

        $display("[%0t] WRITE  addr=0x%0h data=0x%0h slverr=%0b",
                  $time, addr, data, apb.PSLVERR);

        apb.PSEL    = 1'b0;
        apb.PENABLE = 1'b0;

    endtask


    task automatic apb_read(
        input  [ADDR_WIDTH-1:0] addr,
        output [DATA_WIDTH-1:0] data
    );

        @(posedge PCLK);

        apb.PADDR   = addr;
        apb.PWRITE  = 1'b0;
        apb.PSEL    = 1'b1;
        apb.PENABLE = 1'b0;

        @(posedge PCLK);

        apb.PENABLE = 1'b1;

        do @(posedge PCLK);
        while (!apb.PREADY);

        data = apb.PRDATA;

        $display("[%0t] READ   addr=0x%0h data=0x%0h slverr=%0b",
                  $time, addr, data, apb.PSLVERR);

        apb.PSEL    = 1'b0;
        apb.PENABLE = 1'b0;

    endtask


    task automatic apb_write_back_to_back(
        input [ADDR_WIDTH-1:0] addr,
        input [DATA_WIDTH-1:0] data
    );

        apb.PADDR   = addr;
        apb.PWRITE  = 1'b1;
        apb.PWDATA  = data;
        apb.PENABLE = 1'b0;

        @(posedge PCLK);

        apb.PENABLE = 1'b1;

        do @(posedge PCLK);
        while (!apb.PREADY);

        $display("[%0t] WRITE(b2b) addr=0x%0h data=0x%0h slverr=%0b",
                  $time, addr, data, apb.PSLVERR);

    endtask


    logic [DATA_WIDTH-1:0] rdata;

    initial begin

        $display("=========================================================");
        $display(" APB Slave + SVA Checker - Directed Test");
        $display("=========================================================");

        //-----------------------------------------------------------------
        // Reset
        //-----------------------------------------------------------------
        PRESETn = 0;
        apb_idle();

        repeat (3) @(posedge PCLK);

        PRESETn = 1;

        @(posedge PCLK);

        $display("[%0t] --- Reset released ---", $time);


        //-----------------------------------------------------------------
        // Test 1
        //-----------------------------------------------------------------
        $display("[%0t] --- Test 1: basic write/read, 0 wait states ---",
                 $time);

        apb_write(8'h00, 32'hDEAD_BEEF);

        apb_read(8'h00, rdata);

        if (rdata !== 32'hDEAD_BEEF)
            $error("Test 1 FAILED: expected 0xDEADBEEF, got 0x%0h",
                   rdata);
        else
            $display("Test 1 PASSED");


        apb_idle();

        repeat (2) @(posedge PCLK);


        //-----------------------------------------------------------------
        // Test 2
        //-----------------------------------------------------------------
        $display("[%0t] --- Test 2: configure 2 wait states ---",
                 $time);

        apb_write(8'h10, 32'h0000_0002);

        apb_write(8'h04, 32'hCAFE_F00D);

        apb_read(8'h04, rdata);

        if (rdata !== 32'hCAFE_F00D)
            $error("Test 2 FAILED: expected 0xCAFEF00D, got 0x%0h",
                   rdata);
        else
            $display("Test 2 PASSED");

        apb_write(8'h10, 32'h0000_0000);

        apb_idle();

        repeat (2) @(posedge PCLK);


        //-----------------------------------------------------------------
        // Test 3
        //-----------------------------------------------------------------
        $display("[%0t] --- Test 3: back-to-back writes ---",
                 $time);

        @(posedge PCLK);

        apb.PSEL = 1'b1;

        apb_write_back_to_back(
            8'h08,
            32'h1111_1111
        );

        apb_write_back_to_back(
            8'h0C,
            32'h2222_2222
        );

        apb.PSEL    = 1'b0;
        apb.PENABLE = 1'b0;


        apb_read(8'h08, rdata);

        if (rdata !== 32'h1111_1111)
            $error("Test 3a FAILED: got 0x%0h", rdata);

        apb_read(8'h0C, rdata);

        if (rdata !== 32'h2222_2222)
            $error("Test 3b FAILED: got 0x%0h", rdata);

        $display("Test 3 PASSED");


        apb_idle();

        repeat (2) @(posedge PCLK);


        //-----------------------------------------------------------------
        // Test 4
        //-----------------------------------------------------------------
        $display("[%0t] --- Test 4: out-of-range address ---",
                 $time);

        apb_write(8'h40, 32'hFFFF_FFFF);

        if (!apb.PSLVERR)
            $error("Test 4 FAILED: expected PSLVERR on out-of-range address");
        else
            $display("Test 4 PASSED (PSLVERR correctly asserted)");


        apb_idle();

        repeat (3) @(posedge PCLK);
      //-------------------------------------------------------------
      // Test 5: read WAIT_CFG, wait states 1 and 3
      //-------------------------------------------------------------
      $display("[%0t] --- Test 5: WAIT_CFG read, 1 and 3 wait states ---", $time);

      apb_read(8'h10, rdata);
      if (rdata !== 32'h0) $error("Test 5a FAILED: WAIT_CFG reset value 0x%0h", rdata);

      apb_write(8'h10, 32'h1);
      apb_write(8'h00, 32'hA5A5_A5A5);
      apb_read (8'h00, rdata);
      if (rdata !== 32'hA5A5_A5A5) $error("Test 5b FAILED: got 0x%0h", rdata);

      apb_write(8'h10, 32'h3);
      apb_write(8'h04, 32'h5A5A_5A5A);
      apb_read (8'h04, rdata);
      if (rdata !== 32'h5A5A_5A5A) $error("Test 5c FAILED: got 0x%0h", rdata);

      apb_read(8'h10, rdata);
      if (rdata !== 32'h3) $error("Test 5d FAILED: WAIT_CFG read 0x%0h", rdata);

      apb_write(8'h10, 32'h0);
      $display("Test 5 DONE");

      apb_idle();
      repeat (3) @(posedge PCLK);


        //-----------------------------------------------------------------
        // Negative tests
        //-----------------------------------------------------------------

        $display("=========================================================");
        $display(" NEGATIVE TESTS - checker SHOULD report errors below");
        $display("=========================================================");

        // Violation A
        $display("[%0t] --- Violation A: PENABLE with PSEL in same cycle ---",
                 $time);

        @(posedge PCLK);

        force apb.PSEL    = 1'b1;
        force apb.PENABLE = 1'b1;
        force apb.PADDR   = 8'h00;
        force apb.PWRITE  = 1'b1;
        force apb.PWDATA  = 32'hBAD0_0001;

        @(posedge PCLK);

        release apb.PSEL;
        release apb.PENABLE;
        release apb.PADDR;
        release apb.PWRITE;
        release apb.PWDATA;

        apb_idle();

        repeat (2) @(posedge PCLK);


        // Violation B
        $display("[%0t] --- Violation B: PADDR changes mid-transfer ---",
                 $time);

        @(posedge PCLK);

        apb.PADDR   = 8'h00;
        apb.PWRITE  = 1'b1;
        apb.PWDATA  = 32'h1234_5678;
        apb.PSEL    = 1'b1;
        apb.PENABLE = 1'b0;

        @(posedge PCLK);

        apb.PENABLE = 1'b1;

        force apb.PADDR = 8'h04;

        @(posedge PCLK);

        release apb.PADDR;

        apb_idle();

        repeat (2) @(posedge PCLK);


        // Violation C
        $display("[%0t] --- Violation C: PENABLE without PSEL ---",
                 $time);

        @(posedge PCLK);

        force apb.PENABLE = 1'b1;
        force apb.PSEL    = 1'b0;

        @(posedge PCLK);

        release apb.PENABLE;
        release apb.PSEL;

        apb_idle();

        repeat (3) @(posedge PCLK);
      $display("Functional coverage = %0.2f%%", $get_coverage());

        //-----------------------------------------------------------------
        // Finish
        //-----------------------------------------------------------------

        $display("=========================================================");
        $display(" All tests complete.");
        $display("=========================================================");

        $finish;

    end

endmodule
