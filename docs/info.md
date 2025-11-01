<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

It’s a Moore FSM with spaced change/refund pulses and a small datapath for credit/selection.

States:
st_select → st_vend → (st_mc_pulse ↔ st_mc_gap)* → st_select
st_select → (st_refund_pulse ↔ st_refund_gap)* → st_select

## Inputs  
- coin (1 bit): rising-edge–counted +1 credit per pulse (capped at 7).
- btn (4 bits): user command sampled on the transition "0000" → non-zero
                0000 → wait (no command)
                0001 → cancel (clear selection, keep credit)
                0010 → refund (return all credit as spaced pulses)
                0011..1111 → product codes for items 1..13 (internal idx 0..12)

Selection & Pricing

A product code is accepted on a press (must return to 0000 between presses).

Prices depend on the selected index (sel_idx):

idx 0..3 → price 1

idx 4..7 → price 2

idx 8..12 → price 3

When a valid selection exists and credit ≥ price, the FSM vends:

Credit is debited by price in st_vend.

If credit remains, it enters the make-change sequence (spaced pulses).

Otherwise, it returns to st_select.

Refund vs. Make-change

Refund (btn="0010") returns all current credit as pulses with 1-cycle gaps.

Make-change happens after a vend if debit left credit > 0; same pulse/gap pattern.



Outputs (Moore) dispense = '1' only while in dispense_product (exactly one clock cycle). change = '1' only while in return_change (exactly one clock cycle).

Timing/Reset reset is asynchronous, active-high: immediately sends the FSM to idle. State updates on the rising edge of clk. Inputs are sampled synchronously; give them setup/hold around the rising edge. The “one-cycle pulse” behavior comes from those terminal states automatically returning to idle on the next clock.
## How to test

todoExplain how to use your project

## External hardware

todoList external hardware used in your project (e.g. PMOD, LED display, etc), if any
