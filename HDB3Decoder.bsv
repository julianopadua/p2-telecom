import GetPut::*;
import Connectable::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import Assert::*;
import ThreeLevelIO::*;

// Interface para o decodificador HDB3
interface HDB3Decoder;
    interface Put#(Symbol) in; // Entrada de símbolos HDB3
    interface Get#(Bit#(1)) out; // Saída de bits decodificados
endinterface

// Estados do decodificador HDB3
typedef enum {
    IDLE_OR_S1, // Estado inicial ou símbolo 1
    S2,         // Estado para símbolo 2
    S3,         // Estado para símbolo 3
    S4          // Estado para símbolo 4
} DecoderState deriving (Bits, Eq, FShow);

// Módulo que implementa o decodificador HDB3
module mkHDB3Decoder(HDB3Decoder);
    // Vetor de FIFOs para armazenar símbolos intermediários
    Vector#(4, FIFOF#(Symbol)) symbol_fifos <- replicateM(mkPipelineFIFOF);
    Reg#(Bool) is_last_pulse_positive <- mkReg(False); // Registro para o último pulso
    Reg#(DecoderState) current_state <- mkReg(IDLE_OR_S1); // Estado atual do decodificador

    // Conectando FIFOs em série para criar um pipeline
    for (Integer i = 0; i < 3; i = i + 1)
        mkConnection(toGet(symbol_fifos[i+1]), toPut(symbol_fifos[i]));

    // Interface de entrada para símbolos
    interface in = toPut(symbol_fifos[3]);

    // Interface de saída para bits decodificados
    interface Get out;
        method ActionValue#(Bit#(1)) get;
            // Obtém os símbolos recentes dos FIFOs
            let recent_symbols = tuple4(symbol_fifos[0].first, symbol_fifos[1].first, symbol_fifos[2].first, symbol_fifos[3].first);
            let decoded_value = 0; // Valor decodificado padrão

            // Lógica de decodificação baseada no estado atual
            case (current_state)
                IDLE_OR_S1:
                    // Verifica padrões de símbolos para transição de estado
                    if (
                        (is_last_pulse_positive && recent_symbols == tuple4(Z, Z, Z, P)) ||
                        (!is_last_pulse_positive && recent_symbols == tuple4(Z, Z, Z, N))
                    ) action
                        current_state <= S2;
                    endaction
                    else if (
                        (recent_symbols == tuple4(P, Z, Z, P)) ||
                        (recent_symbols == tuple4(N, Z, Z, N))
                    ) action
                        current_state <= S2;
                        is_last_pulse_positive <= !is_last_pulse_positive; // Alterna o sinal do último pulso
                    endaction
                    else if (tpl_1(recent_symbols) != Z) action
                        decoded_value = 1; // Decodifica um '1' se o símbolo não for zero
                        is_last_pulse_positive <= !is_last_pulse_positive;
                    endaction
                S2:
                    action
                        current_state <= S3;
                    endaction
                S3:
                    action
                        current_state <= S4;
                    endaction
                S4:
                    action
                        current_state <= IDLE_OR_S1; // Retorna ao estado inicial
                    endaction
            endcase

            // Remove o símbolo mais antigo do FIFO
            symbol_fifos[0].deq;
            return decoded_value; // Retorna o valor decodificado
        endmethod
    endinterface
endmodule
