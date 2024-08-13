import TriState::*;
import GetPut::*;
import BUtils::*;
import FIFOF::*;
import Assert::*;

typedef 32 CyclesPerSymbol;

interface ThreeLevelIO;
    interface ThreeLevelIOPins pins;
    interface Put#(Symbol) in;
    interface Get#(Symbol) out;
endinterface

typedef enum { N, Z, P } Symbol deriving (Eq, Bits, FShow);

interface ThreeLevelIOPins;
    (* always_ready *)
    method Inout#(Bit#(1)) txp;
    (* always_ready *)
    method Inout#(Bit#(1)) txn;
    (* always_ready, always_enabled, prefix="" *)
    method Action recv(Bit#(1) rxp_n, Bit#(1) rxn_n);

    (* always_ready *)
    method Bool dbg1;
endinterface

module mkThreeLevelIO#(Bool sync_to_line_clock)(ThreeLevelIO);
    LBit#(CyclesPerSymbol) counter_max_value = fromInteger(valueOf(CyclesPerSymbol) - 1);
    Reg#(LBit#(CyclesPerSymbol)) counter_reset_value <- mkReg(counter_max_value);
    Reg#(LBit#(CyclesPerSymbol)) counter <- mkReg(counter_max_value);

    Reg#(Bit#(1)) txp_in <- mkReg(0);
    Reg#(Bit#(1)) txn_in <- mkReg(0);
    Reg#(Bool) tx_en <- mkReg(False);
    TriState#(Bit#(1)) txp_zbuf <- mkTriState(tx_en, txp_in);
    TriState#(Bit#(1)) txn_zbuf <- mkTriState(tx_en, txn_in);

    FIFOF#(Symbol) fifo_tx <- mkFIFOF;
    Reg#(Bool) first_output_produced <- mkReg(False);
    continuousAssert (!first_output_produced || fifo_tx.notEmpty, "E1 TX was not fed fast enough");

    rule produce_output;
        let level = fifo_tx.first;
        let counter_mid_value = counter_max_value >> 1;

        if (counter < counter_mid_value) begin
            level = Z;
        end

        case (level)
            N: begin
                txp_in <= 0;
                txn_in <= 1;
                tx_en <= True;
            end
            Z: begin
                txp_in <= 0;
                txn_in <= 0;
                tx_en <= False;
            end
            P: begin
                txp_in <= 1;
                txn_in <= 0;
                tx_en <= True;
            end
        endcase

        if (counter == 0) begin
            fifo_tx.deq;
        end

        first_output_produced <= True;
        counter <= (counter == 0) ? counter_reset_value : counter - 1;
    endrule

    Reg#(Bit#(3)) rxp_sync <- mkReg('b111);
    Reg#(Bit#(3)) rxn_sync <- mkReg('b111);
    RWire#(Maybe#(Symbol)) fifo_rx_w <- mkRWire;
    FIFOF#(Symbol) fifo_rx <- mkFIFOF;

    continuousAssert(!isValid(fifo_rx_w.wget) || fifo_rx.notFull, "E1 RX was not consumed fast enough");

    rule fifo_rx_enq;
        if (isValid(fifo_rx_w.wget)) begin
            let value = fromMaybe(fifo_rx_w.wget);
            fifo_rx.enq(value);
        end
    endrule

    interface ThreeLevelIOPins pins;
        method txp = txp_zbuf.io;
        method txn = txn_zbuf.io;
        method Action recv(Bit#(1) rxp_n, Bit#(1) rxn_n);
            rxp_sync <= {rxp_n, rxp_sync[2:1]};
            rxn_sync <= {rxn_n, rxn_sync[2:1]};

            let sample_at_counter = sync_to_line_clock ? 0 : (counter_reset_value >> 2);
            if (counter == sample_at_counter) begin
                let value = case ({rxp_sync[1], rxn_sync[1]})
                    2'b00: Z;
                    2'b11: Z;
                    2'b01: P;
                    2'b10: N;
                endcase;
                fifo_rx_w.wset(Valid value);
            end

            counter <= (counter == 0) ? counter_reset_value : counter - 1;

            if (sync_to_line_clock && (rxp_sync[1:0] == 'b01 || rxn_sync[1:0] == 'b01)) begin
                // Adjust counter_reset_value based on edge detection
                if (counter < (counter_reset_value >> 2)) begin
                    counter_reset_value <= counter_reset_value + 1;
                end else if (counter > (counter_reset_value >> 2)) begin
                    counter_reset_value <= counter_reset_value - 1;
                end
            end
        endmethod

        method Bool dbg1 = isValid(fifo_rx_w.wget);
    endinterface

    interface out = toGet(fifo_rx);
    interface in = toPut(fifo_tx);
endmodule
