import GetPut::*;
import Connectable::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import Assert::*;
import ThreeLevelIO::*;

interface HDB3Decoder;
    interface Put#(Symbol) in;
    interface Get#(Bit#(1)) out;
endinterface

typedef enum {
    IDLE_OR_S1,
    S2,
    S3,
    S4
} State deriving (Bits, Eq, FShow);

module mkHDB3Decoder(HDB3Decoder);
    Vector#(4, FIFOF#(Symbol)) fifos <- replicateM(mkPipelineFIFOF);
    Reg#(Bool) last_pulse_p <- mkReg(False);
    Reg#(State) state <- mkReg(IDLE_OR_S1);

    for (Integer i = 0; i < 3; i = i + 1)
        mkConnection(toGet(fifos[i+1]), toPut(fifos[i]));

    interface in = toPut(fifos[3]);

    interface Get out;
        method ActionValue#(Bit#(1)) get;
            let sym0 = fifos[0].first;
            let sym1 = fifos[1].first;
            let sym2 = fifos[2].first;
            let sym3 = fifos[3].first;
            let value = 0;

            // Decodificar com base nos padrões HDB3
            if (sym0 == P || sym0 == N) begin
                value = 1;  // Pulso positivo ou negativo corresponde a 1
                last_pulse_p <= (sym0 == P);
            end else if (sym0 == Z) begin
                value = 0;  // Zero corresponde a 0
            end

            // Detectar e decodificar sequências especiais
            if (sym3 == Z && sym2 == Z && sym1 == Z) begin
                if ((sym0 == P && last_pulse_p) || (sym0 == N && !last_pulse_p)) begin
                    value = 0;  // Sequência especial ZZZP ou ZZZN após pulso oposto
                end
            end

            fifos[0].deq;  // Avançar na fila
            return value;
        endmethod
    endinterface
endmodule


