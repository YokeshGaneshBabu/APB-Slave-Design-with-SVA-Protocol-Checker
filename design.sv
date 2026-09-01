//=====================================================================
// apb_if.sv
//=====================================================================
interface apb_if #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
) (
    input logic PCLK,
    input logic PRESETn
);

    logic [ADDR_WIDTH-1:0] PADDR;
    logic                  PSEL;
    logic                  PENABLE;
    logic                  PWRITE;
    logic [DATA_WIDTH-1:0] PWDATA;
    logic                  PREADY;
    logic [DATA_WIDTH-1:0] PRDATA;
    logic                  PSLVERR;

    modport master (
        input  PCLK, PRESETn, PREADY, PRDATA, PSLVERR,
        output PADDR, PSEL, PENABLE, PWRITE, PWDATA
    );

    modport slave (
        input  PCLK, PRESETn, PADDR, PSEL, PENABLE, PWRITE, PWDATA,
        output PREADY, PRDATA, PSLVERR
    );

    modport monitor (
        input PCLK, PRESETn, PADDR, PSEL, PENABLE, PWRITE, PWDATA,
              PREADY, PRDATA, PSLVERR
    );

endinterface


//=====================================================================
// apb_slave.sv
//=====================================================================
module apb_slave #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
) (
    apb_if.slave apb
);

    typedef enum logic [1:0] {IDLE, SETUP, ACCESS} state_t;
    state_t state, next_state;

    logic [DATA_WIDTH-1:0] regs [0:3];
    logic [1:0]            wait_cfg;
    logic [1:0]            wait_cnt;
    logic                  addr_valid;
    logic [DATA_WIDTH-1:0] rdata_reg;

    // Address decode
    assign addr_valid =
        (apb.PADDR[1:0] == 2'b00) &&
        (apb.PADDR <= 8'h10);

    //-----------------------------------------------------------------
    // FSM state register
    //-----------------------------------------------------------------
    always_ff @(posedge apb.PCLK or negedge apb.PRESETn) begin
        if (!apb.PRESETn)
            state <= IDLE;
        else
            state <= next_state;
    end

    //-----------------------------------------------------------------
    // FSM next-state logic
    //-----------------------------------------------------------------
    always_comb begin
        next_state = state;

        case (state)

            IDLE:
                next_state = apb.PSEL ? SETUP : IDLE;

            SETUP:
                next_state = ACCESS;

            ACCESS: begin
                if (apb.PENABLE && (wait_cnt == 0))
                    next_state = apb.PSEL ? SETUP : IDLE;
                else
                    next_state = ACCESS;
            end

            default:
                next_state = IDLE;

        endcase
    end

    //-----------------------------------------------------------------
    // Wait-state counter
    //-----------------------------------------------------------------
    always_ff @(posedge apb.PCLK or negedge apb.PRESETn) begin
        if (!apb.PRESETn)
            wait_cnt <= 2'b00;
        else if (state == SETUP)
            wait_cnt <= wait_cfg;
        else if (state == ACCESS && wait_cnt != 0)
            wait_cnt <= wait_cnt - 1'b1;
    end

    //-----------------------------------------------------------------
    // PREADY
    //-----------------------------------------------------------------
    assign apb.PREADY =
        (state == ACCESS) &&
        (wait_cnt == 0);

    //-----------------------------------------------------------------
    // Register write
    //-----------------------------------------------------------------
    always_ff @(posedge apb.PCLK or negedge apb.PRESETn) begin

        if (!apb.PRESETn) begin
            regs[0]  <= '0;
            regs[1]  <= '0;
            regs[2]  <= '0;
            regs[3]  <= '0;
            wait_cfg <= 2'b00;
        end

        else if (state == ACCESS && apb.PREADY) begin

            if (addr_valid && apb.PWRITE) begin

                case (apb.PADDR)

                    8'h00:
                        regs[0] <= apb.PWDATA;

                    8'h04:
                        regs[1] <= apb.PWDATA;

                    8'h08:
                        regs[2] <= apb.PWDATA;

                    8'h0C:
                        regs[3] <= apb.PWDATA;

                    8'h10:
                        wait_cfg <= apb.PWDATA[1:0];

                    default:
                        ;

                endcase

            end

        end

    end

    //-----------------------------------------------------------------
    // Read data
    //-----------------------------------------------------------------
    always_comb begin

        case (apb.PADDR)

            8'h00:
                rdata_reg = regs[0];

            8'h04:
                rdata_reg = regs[1];

            8'h08:
                rdata_reg = regs[2];

            8'h0C:
                rdata_reg = regs[3];

            8'h10:
                rdata_reg = {30'b0, wait_cfg};

            default:
                rdata_reg = '0;

        endcase

    end

    assign apb.PRDATA = rdata_reg;

    //-----------------------------------------------------------------
    // PSLVERR
    //
    // PSLVERR is combinational and only asserted during the
    // completing ACCESS cycle.
    //-----------------------------------------------------------------
    assign apb.PSLVERR =
        (state == ACCESS) &&
        apb.PENABLE &&
        apb.PREADY &&
        !addr_valid;

endmodule


//=====================================================================
// apb_checker.sv
//=====================================================================
module apb_checker #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
) (
    apb_if.slave apb
);

    //-----------------------------------------------------------------
    // A1: SETUP must be followed by ACCESS
    //-----------------------------------------------------------------
    property p_setup_then_access;
        @(posedge apb.PCLK) disable iff (!apb.PRESETn)
        ($rose(apb.PSEL) |-> (!apb.PENABLE) ##1 apb.PENABLE);
    endproperty

    a_setup_then_access:
        assert property (p_setup_then_access)
        else $error("[APB_CHK] PENABLE did not assert exactly one cycle after PSEL");


    //-----------------------------------------------------------------
    // A2: PADDR stable while waiting
    //-----------------------------------------------------------------
    property p_addr_stable;
        @(posedge apb.PCLK) disable iff (!apb.PRESETn)
        (apb.PSEL && apb.PENABLE && !apb.PREADY)
        |=> $stable(apb.PADDR);
    endproperty

    a_addr_stable:
        assert property (p_addr_stable)
        else $error("[APB_CHK] PADDR changed mid-transfer (before PREADY)");


    //-----------------------------------------------------------------
    // A3: PWRITE stable while waiting
    //-----------------------------------------------------------------
    property p_write_stable;
        @(posedge apb.PCLK) disable iff (!apb.PRESETn)
        (apb.PSEL && apb.PENABLE && !apb.PREADY)
        |=> $stable(apb.PWRITE);
    endproperty

    a_write_stable:
        assert property (p_write_stable)
        else $error("[APB_CHK] PWRITE changed mid-transfer (before PREADY)");


    //-----------------------------------------------------------------
    // A4: PWDATA stable while waiting on a write
    //-----------------------------------------------------------------
    property p_wdata_stable;
        @(posedge apb.PCLK) disable iff (!apb.PRESETn)
        (apb.PSEL && apb.PENABLE && apb.PWRITE && !apb.PREADY)
        |=> $stable(apb.PWDATA);
    endproperty

    a_wdata_stable:
        assert property (p_wdata_stable)
        else $error("[APB_CHK] PWDATA changed mid-transfer (before PREADY) on a write");


    //-----------------------------------------------------------------
    // A5: PSEL must remain asserted while transfer is pending
    //-----------------------------------------------------------------
    property p_psel_no_early_drop;
        @(posedge apb.PCLK) disable iff (!apb.PRESETn)
        (apb.PSEL && apb.PENABLE && !apb.PREADY)
        |=> apb.PSEL;
    endproperty

    a_psel_no_early_drop:
        assert property (p_psel_no_early_drop)
        else $error("[APB_CHK] PSEL deasserted before transfer completed (PREADY)");


    //-----------------------------------------------------------------
    // A6: PSLVERR only during completing ACCESS
    //-----------------------------------------------------------------
    property p_slverr_only_on_completion;
        @(posedge apb.PCLK) disable iff (!apb.PRESETn)
        apb.PSLVERR |-> (apb.PSEL && apb.PENABLE && apb.PREADY);
    endproperty

    a_slverr_only_on_completion:
        assert property (p_slverr_only_on_completion)
        else $error("[APB_CHK] PSLVERR asserted outside a completing ACCESS phase");


    //-----------------------------------------------------------------
    // A7: Reset must leave APB idle
    //-----------------------------------------------------------------
    property p_reset_idle;
        @(posedge apb.PCLK)
        $rose(apb.PRESETn) |-> (!apb.PSEL && !apb.PENABLE);
    endproperty

    a_reset_idle:
        assert property (p_reset_idle)
        else $error("[APB_CHK] PSEL/PENABLE not idle immediately after reset deassertion");


    //-----------------------------------------------------------------
    // A8: PENABLE cannot be high without PSEL
    //-----------------------------------------------------------------
    property p_no_enable_without_sel;
        @(posedge apb.PCLK) disable iff (!apb.PRESETn)
        apb.PENABLE |-> apb.PSEL;
    endproperty

    a_no_enable_without_sel:
        assert property (p_no_enable_without_sel)
        else $error("[APB_CHK] PENABLE asserted while PSEL is low");


    //-----------------------------------------------------------------
    // Functional coverage
    //-----------------------------------------------------------------
    covergroup cg_apb_transfers
        @(posedge apb.PCLK iff
        (apb.PSEL && apb.PENABLE && apb.PREADY));

        cp_write:
            coverpoint apb.PWRITE;

        cp_slverr:
            coverpoint apb.PSLVERR;

        cp_addr:
            coverpoint apb.PADDR {
                bins valid_regs[] =
                    {8'h00, 8'h04, 8'h08, 8'h0C, 8'h10};

                bins invalid_region = default;
            }

    endgroup

    cg_apb_transfers cg_inst = new();

endmodule


//=====================================================================
// Bind checker to APB slave
//=====================================================================
bind apb_slave apb_checker #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
) u_apb_checker (
    .apb (apb)
);
