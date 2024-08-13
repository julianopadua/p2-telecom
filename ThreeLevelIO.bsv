import TriState::*;
import GetPut::*;
import BUtils::*;
import FIFOF::*;
import Assert::*;

// Define o número de ciclos por símbolo
typedef 32 CyclesPerSymbol;

// Define a interface de entrada/saída de três níveis
interface ThreeLevelIO;
    interface ThreeLevelIOPins pins;
    interface Put#(Symbol) in;
    interface Get#(Symbol) out;
endinterface

// Define os símbolos utilizados na comunicação
typedef enum { N, Z, P } Symbol deriving (Eq, Bits, FShow);

// Define os pinos para a interface de entrada/saída de três níveis
interface ThreeLevelIOPins;
    (* always_ready *)
    method Inout#(Bit#(1)) txp; // Pino de transmissão positivo
    (* always_ready *)
    method Inout#(Bit#(1)) txn; // Pino de transmissão negativo
    (* always_ready, always_enabled, prefix="" *)
    method Action recv(Bit#(1) rxp_n, Bit#(1) rxn_n); // Método de recepção

    (* always_ready *)
    method Bool dbg1; // Sinal de debug
    //(* always_ready *)
    //method Bool dbg2;
endinterface

// Módulo principal que implementa a interface de entrada/saída de três níveis
module mkThreeLevelIO#(Bool sync_with_line_clock)(ThreeLevelIO);
    // Define o valor máximo do contador com base no número de ciclos por símbolo
    LBit#(CyclesPerSymbol) max_counter_value = fromInteger(valueOf(CyclesPerSymbol) - 1);
    
    // Registros para o valor de reset do contador e o contador em si
    Reg#(LBit#(CyclesPerSymbol)) reset_counter_value <- mkReg(max_counter_value);
    Reg#(LBit#(CyclesPerSymbol)) cycle_counter <- mkReg(max_counter_value);

    // Registros para os pinos de transmissão e o buffer de três estados
    Reg#(Bit#(1)) txp_state <- mkReg(0);
    Reg#(Bit#(1)) txn_state <- mkReg(0);
    Reg#(Bool) transmission_enable <- mkReg(False);
    TriState#(Bit#(1)) txp_buffer <- mkTriState(transmission_enable, txp_state);
    TriState#(Bit#(1)) txn_buffer <- mkTriState(transmission_enable, txn_state);

    // FIFO para transmissão de símbolos
    FIFOF#(Symbol) symbol_fifo_tx <- mkFIFOF;

    // Registro para indicar se a primeira saída foi produzida
    Reg#(Bool) is_first_output_produced <- mkReg(False);
    continuousAssert (!is_first_output_produced || symbol_fifo_tx.notEmpty, "E1 TX não foi alimentado rápido o suficiente");

    // Regra para produzir a saída com base nos símbolos do FIFO
    rule produce_output;
        let current_level = symbol_fifo_tx.first;

        let mid_counter_value = max_counter_value >> 1;
        if (cycle_counter < mid_counter_value)  // Retornar para zero
            current_level = Z;

        // Ajusta os sinais de transmissão com base no símbolo atual
        case (current_level)
            N:
                action
                    txp_state <= 0;
                    txn_state <= 1;
                    transmission_enable <= True;
                endaction
            Z:
                action
                    txp_state <= 0;
                    txn_state <= 0;
                    transmission_enable <= False;
                endaction
            P:
                action
                    txp_state <= 1;
                    txn_state <= 0;
                    transmission_enable <= True;
                endaction
        endcase

        // Desenfileira o próximo símbolo quando o contador chega a zero
        if (cycle_counter == 0) begin
            symbol_fifo_tx.deq;
        end

        is_first_output_produced <= True;
    endrule

    // Registros para sincronização dos sinais de recepção
    Reg#(Bit#(3)) rxp_sync_reg <- mkReg('b111);
    Reg#(Bit#(3)) rxn_sync_reg <- mkReg('b111);
    RWire#(Symbol) fifo_rx_wire <- mkRWire;
    FIFOF#(Symbol) symbol_fifo_rx <- mkFIFOF;

    continuousAssert(!isValid(fifo_rx_wire.wget) || symbol_fifo_rx.notFull, "E1 RX não foi consumido rápido o suficiente");

    // Regra para enfileirar símbolos recebidos no FIFO
    rule fifo_rx_enqueue (fifo_rx_wire.wget matches tagged Valid .value);
        symbol_fifo_rx.enq(value);
    endrule

    // Implementação da interface de pinos de entrada/saída de três níveis
    interface ThreeLevelIOPins pins;
        method txp = txp_buffer.io; // Atribuição ao buffer do pino de transmissão positivo
        method txn = txn_buffer.io; // Atribuição ao buffer do pino de transmissão negativo

        // Método de recepção que atualiza os registros de sincronização
        method Action recv(Bit#(1) rxp_n, Bit#(1) rxn_n);
            rxp_sync_reg <= {rxp_n, rxp_sync_reg[2:1]};
            rxn_sync_reg <= {rxn_n, rxn_sync_reg[2:1]};

            // Define o instante para amostrar o sinal de entrada
            let sample_point = sync_with_line_clock ? 0 : 17;
            if (cycle_counter == sample_point) begin
                let value = case ({rxp_sync_reg[1], rxn_sync_reg[1]})
                    2'b00: Z;
                    2'b11: Z;
                    2'b01: P;
                    2'b10: N;
                endcase;
                fifo_rx_wire.wset(value);
            end

            // Atualiza o contador
            cycle_counter <= cycle_counter == 0 ? reset_counter_value : cycle_counter - 1;

            // Implementa o DPLL para ajuste do contador
            if (sync_with_line_clock) begin
                let rising_edge_detected = rxp_sync_reg[1:0] == 'b01 || rxn_sync_reg[1:0] == 'b01;  // {bit_atual, bit_anterior}
                let optimal_sample_point = reset_counter_value >> 2;

                if (rising_edge_detected) begin 
                    let new_reset_counter_value = max_counter_value;

                    if (cycle_counter > optimal_sample_point) begin
                        new_reset_counter_value = max_counter_value - 1; // Ajusta para encurtar o ciclo
                    end
                    else if (cycle_counter < optimal_sample_point) begin
                        new_reset_counter_value = max_counter_value + 1; // Ajusta para alongar o ciclo
                    end

                    reset_counter_value <= new_reset_counter_value;
                end
            end
        endmethod

        method dbg1 = isValid(fifo_rx_wire.wget); // Sinal de debug para verificar se há um valor válido no FIFO
        //method dbg2 = symbol_fifo_rx.notFull;
        //method dbg2 = !is_first_output_produced || symbol_fifo_tx.notEmpty;
    endinterface

    interface out = toGet(symbol_fifo_rx); // Interface de saída que consome do FIFO de recepção
    interface in = toPut(symbol_fifo_tx); // Interface de entrada que enfileira no FIFO de transmissão
endmodule
