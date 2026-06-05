# CAN 2.0A Controller IP 


**Key Features:**
- CAN 2.0A standard compliance (11-bit identifier, data frames)
- APB3 slave interface for CPU access
- Configurable bit timing with synchronization
- Automatic bit stuffing/de-stuffing
- CRC-15 generation and checking
- Arbitration handling
- Error detection and management (TEC/REC counters, bus-off)
- Acceptance filtering with configurable mask
- Interrupt generation for all events
- Loopback and listen-only modes

## Architecture

### Top-Level Module: `can_controller_top.v`

The top-level module integrates all verified sub-blocks:



<img width="727" height="521" alt="can drawio" src="https://github.com/user-attachments/assets/22c4ed3b-5140-49bd-bbfc-db06e1a60977" />



## Module List

### Core Modules (All Verified)

| Module | File | Description |
|--------|------|-------------|
| APB Slave | `can_apb_slave.v` | APB3 interface, command register | 
| Register File | `can_reg_file.v` | Configuration and status registers | 
| Bit Timing | `can_bit_timing.v` | Bit rate generator with sync | 
| TX FSM | `tx_fsm.v` | Transmit state machine | 
| RX FSM | `rx_fsm.v` | Receive state machine | 
| Bit Stuffing | `bit_stuffing.v` | TX stuffing, RX de-stuffing | 
| CRC Generator | `crc.v` | CRC-15 calculation | 
| Arbitration | `arbitration.v` | Arbitration loss detection | 
| Error Detector | `error_detector.v` | TEC/REC counters, bus-off |  
| Acceptance Filter | `acceptance_filter.v` | ID filtering with mask |
| Interrupt Controller | `interrupt.v` | Event interrupt generation | 
| **Top-Level** | `can_controller_top.v` | **Complete integration** | 

### Testbenches

All modules include comprehensive self-checking testbenches:

- `tb_can_apb_slave.v` - APB protocol compliance
- `tb_can_reg_file.v` - Register access and sticky bits
- `tb_bit_timing.v` - Bit timing and synchronization
- `tb_bit_stuffing.v` - Bit stuffing viewer
- `tb_crc.v` - CRC calculation verification
- `tb_acceptance_filter.v` - ID filtering tests
- `tb_tx_fsm.v` - Full frame transmission
- `tb_rx_fsm.v` - Full frame reception
- `tb_arbitration.v` - Arbitration scenarios
- `tb_error_detector.v` - Error counter behavior
- `tb_interrupt.v` - Interrupt generation
- `tb_can_controller_top.v` - **End-to-end integration test**

## Register Map

Base address: 0x0000 (byte-addressed, 16-bit words)

| Address | Register | Access | Description |
|---------|----------|--------|-------------|
| 0x00 | MODE | R/W | Mode control (reset_mode, loopback, listen_only) |
| 0x02 | INT_EN | R/W | Interrupt enable mask |
| 0x04 | BTR | R/W | Bit Timing Register (BRP, TSEG1, TSEG2, SJW) |
| 0x06 | ACR | R/W | Acceptance Code Register |
| 0x08 | AMR | R/W | Acceptance Mask Register |
| 0x0A | TX_ID | R/W | Transmit ID (11-bit) |
| 0x0C | TX_DLC | R/W | Transmit DLC (4-bit, 0-8) |
| 0x0E | TX_DATA0 | R/W | TX data bytes 0-1 |
| 0x10 | TX_DATA1 | R/W | TX data bytes 2-3 |
| 0x12 | TX_DATA2 | R/W | TX data bytes 4-5 |
| 0x14 | TX_DATA3 | R/W | TX data bytes 6-7 |
| 0x16 | STATUS | RO | Status (tx_busy, tx_done, rx_ready, arb_lost, bus_off) |
| 0x18 | IR | RO | Interrupt Register |
| 0x1A | TEC | RO | Transmit Error Counter |
| 0x1C | REC | RO | Receive Error Counter |
| 0x1E | ERR_CODE | RO | Last Error Code |
| 0x20 | RX_ID | RO | Received ID |
| 0x22 | RX_DLC | RO | Received DLC |
| 0x24 | RX_DATA0 | RO | RX data bytes 0-1 |
| 0x26 | RX_DATA1 | RO | RX data bytes 2-3 |
| 0x28 | RX_DATA2 | RO | RX data bytes 4-5 |
| 0x2A | RX_DATA3 | RO | RX data bytes 6-7 |
| 0x2C | COMMAND | WO | Command register (tx_req, tx_abort, rx_release) |

### STATUS Register (0x16) - Sticky Bits

- Bit [0]: `tx_busy` - Level (HIGH during transmission)
- Bit [1]: `tx_done` - Sticky (set on TX complete, clear on read)
- Bit [2]: `rx_ready` - Sticky (set on RX complete, clear on read)
- Bit [3]: `arb_lost` - Sticky (set on arbitration loss, clear on read)
- Bit [4]: `bus_off` - Level (HIGH when node is bus-off)

**Important:** Reading STATUS register clears all sticky bits (tx_done, rx_ready, arb_lost).




## Future Enhancements

- [ ] Add TX/RX FIFOs for multiple messages
- [ ] Implement CAN 2.0B (29-bit extended IDs)
- [ ] Add remote frame support
- [ ] Automatic bus-off recovery
- [ ] DMA support for data transfers
- [ ] Timestamp capture for frames
- [ ] Sleep/wake-up mode


