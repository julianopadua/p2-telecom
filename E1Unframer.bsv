import GetPut::*;
import FIFOF::*;
import Assert::*;

// Definindo o tipo para representar o intervalo de tempo
typedef Bit#(TLog#(32)) TimeSlot;

// Interface para o desemoldurador E1
interface E1Unframer;
    interface Put#(Bit#(1)) in; // Entrada de bits
    interface Get#(Tuple2#(TimeSlot, Bit#(1))) out; // Saída de tupla (intervalo de tempo, bit)
endinterface

// Estados do processo de sincronização
typedef enum {
    UNSYNCED,  // Não sincronizado
    FIRST_FAS, // Primeiro FAS (Frame Alignment Signal)
    FIRST_NFAS, // Primeiro NFAS (Non-Frame Alignment Signal)
    SYNCED     // Sincronizado
} SyncState deriving (Bits, Eq, FShow);

// Módulo que implementa o desemoldurador E1
module mkE1Unframer(E1Unframer);
    FIFOF#(Tuple2#(TimeSlot, Bit#(1))) output_fifo <- mkFIFOF; // FIFO para saída
    Reg#(SyncState) current_state <- mkReg(UNSYNCED); // Estado atual
    Reg#(Bit#(TLog#(8))) current_bit_index <- mkRegU; // Índice do bit atual
    Reg#(TimeSlot) current_timeslot <- mkRegU; // Intervalo de tempo atual
    Reg#(Bool) is_fas_phase <- mkRegU; // Indica se está na fase FAS
    Reg#(Bit#(8)) current_byte <- mkReg(0); // Byte atual sendo construído

    interface out = toGet(output_fifo); // Interface de saída

    // Interface de entrada de bits
    interface Put in;
        method Action put(Bit#(1) incoming_bit);
            // Constrói o novo byte com o bit de entrada
            let updated_byte = {current_byte[6:0], incoming_bit};

            case (current_state)
                UNSYNCED:
                    if (updated_byte[6:0] == 7'b0011011) action // Verifica o padrão FAS
                        current_state <= FIRST_FAS;
                        current_bit_index <= 0;
                        current_timeslot <= 1;
                        is_fas_phase <= True;
                    endaction
                FIRST_FAS:
                    if (current_timeslot == 0 && current_bit_index == 7) action
                        // Intervalo de tempo 0 do NFAS
                        if (updated_byte[6] == 1) action
                            current_state <= FIRST_NFAS;
                            current_bit_index <= 0;
                            current_timeslot <= 1;
                            is_fas_phase <= False;
                        endaction
                        else action
                            current_state <= UNSYNCED;
                        endaction
                    endaction
                    else if (current_bit_index == 7) action
                        current_timeslot <= current_timeslot + 1;
                        current_bit_index <= 0;
                    endaction
                    else action
                        current_bit_index <= current_bit_index + 1;
                    endaction
                FIRST_NFAS:
                    if (current_timeslot == 0 && current_bit_index == 7) action
                        // Intervalo de tempo 0 do FAS
                        if (updated_byte[6:0] == 7'b0011011) action
                            current_state <= SYNCED;
                            current_bit_index <= 0;
                            current_timeslot <= 1;
                            is_fas_phase <= True;
                        endaction
                        else action
                            current_state <= UNSYNCED;
                        endaction
                    endaction
                    else if (current_bit_index == 7) action
                        current_timeslot <= current_timeslot + 1;
                        current_bit_index <= 0;
                    endaction
                    else action
                        current_bit_index <= current_bit_index + 1;
                    endaction
                SYNCED:
                    action
                        if (current_timeslot == 0 && current_bit_index == 7) action
                            // Intervalo de tempo 0, deve verificar
                            if (is_fas_phase) action
                                // Estava em FAS, próximo é NFAS
                                if (updated_byte[6] == 1) action
                                    current_bit_index <= 0;
                                    current_timeslot <= 1;
                                    is_fas_phase <= False;
                                endaction
                                else action
                                    current_state <= UNSYNCED;
                                endaction
                            endaction
                            else action
                                // Estava em NFAS, próximo é FAS
                                if (updated_byte[6:0] == 7'b0011011) action
                                    current_bit_index <= 0;
                                    current_timeslot <= 1;
                                    is_fas_phase <= True;
                                endaction
                                else action
                                    current_state <= UNSYNCED;
                                endaction
                            endaction
                        endaction
                        else if (current_bit_index == 7) action
                            current_timeslot <= current_timeslot + 1;
                            current_bit_index <= 0;
                        endaction
                        else action
                            current_bit_index <= current_bit_index + 1;
                        endaction

                        output_fifo.enq(tuple2(current_timeslot, incoming_bit)); // Enfileira a saída
                    endaction
            endcase

            current_byte <= updated_byte; // Atualiza o byte atual
        endmethod
    endinterface
endmodule
