import GetPut::*;
import FIFOF::*;
import Assert::*;

typedef Bit#(TLog#(32)) Timeslot;

interface E1Unframer;
    interface Put#(Bit#(1)) in;
    interface Get#(Tuple2#(Timeslot, Bit#(1))) out;
endinterface

typedef enum {
    UNSYNCED,
    FIRST_FAS,
    FIRST_NFAS,
    SYNCED
} State deriving (Bits, Eq, FShow);

module mkE1Unframer(E1Unframer);
    FIFOF#(Tuple2#(Timeslot, Bit#(1))) fifo_out <- mkFIFOF;
    Reg#(State) state <- mkReg(UNSYNCED);
    Reg#(Bit#(TLog#(8))) cur_bit <- mkRegU; // Para rastrear o bit atual dentro do byte
    Reg#(Timeslot) cur_ts <- mkRegU; // Para rastrear o índice do timeslot atual
    Reg#(Bool) fas_turn <- mkReg(False); // Indica se estamos esperando FAS ou NFAS
    Reg#(Bit#(8)) cur_byte <- mkReg(0); // Byte atual sendo construído

    interface out = toGet(fifo_out);

    interface Put in;
        method Action put(Bit#(1) b);
            // Construindo o byte atual
            cur_byte <= (cur_byte << 1) | zeroExtend(b);
            cur_bit <= cur_bit + 1;

            // Verifica se completamos um byte (8 bits)
            if (cur_bit == 7) begin
                cur_bit <= 0;
                
                // Verifica o estado atual
                case (state)
                    UNSYNCED: begin
                        if (cur_byte == 7'b0011011) begin // FAS detectado
                            state <= FIRST_FAS;
                            cur_ts <= 1;
                        end
                    end

                    FIRST_FAS: begin
                        if (fas_turn) begin
                            if (cur_byte[6] == 1) begin // Verifica se pode ser NFAS
                                state <= FIRST_NFAS;
                            end else begin
                                state <= UNSYNCED; // Não é um NFAS válido
                            end
                        end else begin
                            state <= UNSYNCED; // Não é uma sequência válida
                        end
                    end

                    FIRST_NFAS: begin
                        if (cur_byte == 7'b0011011) begin // FAS detectado
                            state <= SYNCED;
                            cur_ts <= 1;
                        end else begin
                            state <= UNSYNCED;
                        end
                    end

                    SYNCED: begin
                        if (cur_ts == 0) begin
                            // TS0: valida se é FAS ou NFAS
                            if (fas_turn && cur_byte != 7'b0011011) begin
                                state <= UNSYNCED;
                            end
                            if (!fas_turn && cur_byte[6] != 1) begin
                                state <= UNSYNCED;
                            end
                            fas_turn <= !fas_turn;
                        end else begin
                            // Apenas envia timeslots TS1-31
                            fifo_out.enq(tuple2(cur_ts, cur_byte[7]));
                        end
                        cur_ts <= (cur_ts + 1) % 32;
                    end
                endcase
            end
        endmethod
    endinterface
endmodule
