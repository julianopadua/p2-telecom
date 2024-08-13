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
            let recent_symbols = tuple4(fifos[0].first, fifos[1].first, fifos[2].first, fifos[3].first);
            let value = 0;

    
            match (recent_symbols)
                (tuple4(P, Z, Z, P)),
                (tuple4(N, Z, Z, N)),
                (tuple4(Z, Z, Z, P) when last_pulse_p),
                (tuple4(Z, Z, Z, N) when !last_pulse_p):
                    value = 0;
                    last_pulse_p <= recent_symbols[0] == P;

                (P):
                    value = 1;
                    last_pulse_p <= True;

                (N):
                    value = 1;
                    last_pulse_p <= False;

                (Z):
                    value = 0;

            fifos[0].deq;
            return value;
        endmethod
    endinterface
endmodule

