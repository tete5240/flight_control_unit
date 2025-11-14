// =============================================================
// Simple I2C Master (READ 1 BYTE ONLY)
// 기능 요약:
//   - start 조건 생성
//   - slave 주소 + write 전송
//   - register address 전송
//   - repeated start 생성
//   - slave 주소 + read 전송
//   - slave가 보내는 1바이트 수신
//   - stop 조건 생성
//
// SDA는 open-drain 방식 구현 (0 또는 high-Z)
// =============================================================
module i2c_master(
    input  wire clk,         // 시스템 클럭
    input  wire rst_n,       // 리셋
    output reg  scl,         // I2C SCL (마스터 구동)
    inout  wire sda,         // I2C SDA (open-drain)
    output reg [7:0] data_out, // 슬레이브로부터 읽어온 데이터
    output reg done          // 읽기 완료 신호
);

// -------------------------------------------------------------
// I2C 내부 제어 신호
// -------------------------------------------------------------
reg sda_out; // SDA 라인을 Low로 끌어내릴 때 사용 (0만 출력 가능)
reg sda_oe;  // SDA 출력 활성화 (1이면 '0'을 출력, 0이면 High-Z)

// inout 핀에 대한 open-drain 구현
assign sda = (sda_oe) ? 1'b0 : 1'bz;

// SDA 읽기용
wire sda_in = sda;

// -------------------------------------------------------------
// 파라미터
// -------------------------------------------------------------
localparam SLAVE_ADDR = 7'h68;    // MPU6050 기본 주소(0x68)
localparam REG_ADDR   = 8'h75;    // WHO_AM_I 레지스터(예시)

// I2C SCL 분주기 (느리게 만들기)
reg [15:0] clk_div;
wire scl_tick = (clk_div == 16'd0);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) clk_div <= 0;
    else        clk_div <= clk_div + 1;
end

// -------------------------------------------------------------
// FSM 상태 정의
// -------------------------------------------------------------
typedef enum logic [4:0] {
    IDLE,
    START,
    SEND_ADDR_WR,
    ADDR_WR_ACK,
    SEND_REG,
    REG_ACK,
    RESTART,
    SEND_ADDR_RD,
    ADDR_RD_ACK,
    READ_DATA,
    SEND_NACK,
    STOP,
    DONE
} state_t;

state_t state;

// -------------------------------------------------------------
// 비트 카운터
// -------------------------------------------------------------
reg [3:0] bit_cnt;

// -------------------------------------------------------------
// FSM 동작
// -------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        scl      <= 1;
        sda_oe   <= 0;
        sda_out  <= 0;
        state    <= IDLE;
        bit_cnt  <= 0;
        done     <= 0;
        data_out <= 8'h00;

    end else begin
        if (!scl_tick) begin
            // SCL이 변화해야 I2C 동작이 진행되므로 tick 아니면 대기
            scl <= ~scl;
            return;
        end

        case(state)

        // -----------------------------------------------------
        IDLE
        // -----------------------------------------------------
        IDLE: begin
            done <= 0;
            scl <= 1;
            sda_oe <= 0; // High-Z
            state <= START;
        end

        // -----------------------------------------------------
        START 조건: SDA High→Low while SCL High
        // -----------------------------------------------------
        START: begin
            sda_oe <= 1;   // SDA = 0
            scl    <= 1;
            state  <= SEND_ADDR_WR;
            bit_cnt <= 7;
        end

        // -----------------------------------------------------
        // 7bit 주소 + Write(0)
        // -----------------------------------------------------
        SEND_ADDR_WR: begin
            sda_oe <= 1;
            sda_out <= SLAVE_ADDR[bit_cnt];

            if (scl == 1) begin
                if (bit_cnt == 0) begin
                    state <= ADDR_WR_ACK;
                    sda_oe <= 1;
                    sda_out <= 0; // R/W=0
                end else begin
                    bit_cnt <= bit_cnt - 1;
                end
            end
        end

        // -----------------------------------------------------
        // Slave ACK
        // -----------------------------------------------------
        ADDR_WR_ACK: begin
            sda_oe <= 0; // High-Z (slave drives ACK)
            if (scl == 1) begin
                state <= SEND_REG;
                bit_cnt <= 7;
            end
        end

        // -----------------------------------------------------
        // Register Address 전송
        // -----------------------------------------------------
        SEND_REG: begin
            sda_oe <= 1;
            sda_out <= REG_ADDR[bit_cnt];
            if (scl == 1) begin
                if (bit_cnt == 0) begin
                    state <= REG_ACK;
                end else bit_cnt <= bit_cnt - 1;
            end
        end

        // -----------------------------------------------------
        REG_ACK: begin
            sda_oe <= 0; // High-Z
            if (scl == 1) begin
                state <= RESTART;
            end
        end

        // -----------------------------------------------------
        // Restart 조건
        // -----------------------------------------------------
        RESTART: begin
            sda_oe <= 1;  // SDA Low
            scl <= 1;
            state <= SEND_ADDR_RD;
            bit_cnt <= 7;
        end

        // -----------------------------------------------------
        // 주소 + Read(1)
        // -----------------------------------------------------
        SEND_ADDR_RD: begin
            sda_oe <= 1;
            sda_out <= SLAVE_ADDR[bit_cnt];
            if (scl == 1) begin
                if (bit_cnt == 0) begin
                    sda_out <= 1; // R/W bit = 1
                    state <= ADDR_RD_ACK;
                end else bit_cnt <= bit_cnt - 1;
            end
        end

        // -----------------------------------------------------
        ADDR_RD_ACK
        // -----------------------------------------------------
        ADDR_RD_ACK: begin
            sda_oe <= 0; // High-Z → slave drives ACK
            if (scl == 1) begin
                state <= READ_DATA;
                bit_cnt <= 7;
            end
        end

        // -----------------------------------------------------
        // Slave 데이터 읽기
        // -----------------------------------------------------
        READ_DATA: begin
            sda_oe <= 0; // High-Z (slave drives data)
            if (scl == 1) begin
                data_out[bit_cnt] <= sda_in;
                if (bit_cnt == 0) state <= SEND_NACK;
                else bit_cnt <= bit_cnt - 1;
            end
        end

        // -----------------------------------------------------
        // 마지막 바이트이므로 NACK 전송
        // -----------------------------------------------------
        SEND_NACK: begin
            sda_oe <= 0; // High-Z = NACK
            if (scl == 1) begin
                state <= STOP;
            end
        end

        // -----------------------------------------------------
        // Stop 조건
        // -----------------------------------------------------
        STOP: begin
            sda_oe <= 1;
            sda_out <= 0;
            scl <= 1;

            // SDA High로 해제 → STOP
            sda_oe <= 0;

            state <= DONE;
        end

        DONE: begin
            done <= 1;
        end

        endcase
    end
end

endmodule
