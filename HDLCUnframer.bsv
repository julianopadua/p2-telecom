import GetPut::*;
import FIFOF::*;
import Assert::*;

// Interface para o desemoldurador HDLC
interface HDLCUnframer;
    interface Put#(Bit#(1)) in; // Entrada de bits
    interface Get#(Tuple2#(Bool, Bit#(8))) out; // Saída de tupla (início do quadro, byte do quadro)
endinterface

// Estados do desemoldurador HDLC
typedef enum {
    IDLE,               // Ocioso, esperando um novo quadro
    PROCESS_FRAME,      // Processando bits do quadro
    CHECK_BIT_STUFFING  // Verificando bits de preenchimento
} FrameState deriving (Eq, Bits, FShow);

// Módulo que implementa o desemoldurador HDLC
module mkHDLCUnframer(HDLCUnframer);
    FIFOF#(Tuple2#(Bool, Bit#(8))) output_fifo <- mkFIFOF; // FIFO para saída de quadros
    Reg#(Bool) is_frame_start <- mkReg(True); // Indica o início de um quadro
    Reg#(FrameState) current_state <- mkReg(IDLE); // Estado atual
    Reg#(Bit#(3)) bit_index <- mkReg(0); // Índice do bit atual no byte
    Reg#(Bit#(8)) current_frame_byte <- mkRegU; // Byte atual do quadro
    Reg#(Bit#(8)) recent_bit_window <- mkReg(0); // Janela dos bits recentes

    // Flag HDLC padrão que indica início/fim de quadro
    Bit#(8) hdlc_flag_pattern = 8'b01111110;

    interface out = toGet(output_fifo); // Interface de saída

    // Interface de entrada de bits
    interface Put in;
        method Action put(Bit#(1) incoming_bit);
            // Atualiza a janela dos bits recentes com o novo bit
            let updated_recent_bits = {incoming_bit, recent_bit_window[7:1]};
            // Calcula o próximo índice do bit
            let next_bit_index = bit_index + 1;
            // Atualiza o byte do quadro atual com o novo bit
            let updated_frame_byte = {incoming_bit, current_frame_byte[7:1]};
            // Preserva o estado atual por padrão
            let next_state = current_state;
            // Verifica se há possível bit de preenchimento
            let check_bit_stuffing = updated_recent_bits[7:3] == 5'b11111;

            // Transição de estados com base no estado atual
            case (current_state)
                IDLE:
                    // Verifica o padrão de flag HDLC para iniciar um quadro
                    if (updated_recent_bits == hdlc_flag_pattern) action
                        next_state = PROCESS_FRAME;
                        next_bit_index = 0;
                        is_frame_start <= True;
                    endaction
                PROCESS_FRAME:
                    action
                        // Se o byte estiver completo, enfileira o byte no FIFO
                        if (bit_index == 7) action
                            next_state = check_bit_stuffing ? CHECK_BIT_STUFFING : PROCESS_FRAME;
                            output_fifo.enq(tuple2(is_frame_start, updated_frame_byte));
                            is_frame_start <= False;
                        endaction
                        else if (check_bit_stuffing) action
                            // Transita para verificar bit de preenchimento se necessário
                            next_state = CHECK_BIT_STUFFING;
                        endaction
                        current_frame_byte <= updated_frame_byte;
                    endaction
                CHECK_BIT_STUFFING:
                    if (incoming_bit == 1) action
                        // Flag ou erro detectado
                        next_state = IDLE;
                    endaction
                    else action
                        // Bit de preenchimento detectado, ignora e continua processando o quadro
                        next_state = PROCESS_FRAME;
                        next_bit_index = bit_index;
                    endaction
            endcase

            // Atualiza as variáveis de estado e bits
            recent_bit_window <= updated_recent_bits;
            bit_index <= next_bit_index;
            current_state <= next_state;
        endmethod
    endinterface
endmodule
