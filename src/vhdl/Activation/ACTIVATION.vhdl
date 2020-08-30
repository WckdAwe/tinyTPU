-- Copyright 2018 Jonas Fuhrmann. All rights reserved.
--
-- This project is dual licensed under GNU General Public License version 3
-- and a commercial license available on request.
---------------------------------------------------------------------------
-- For non commercial use only:
-- This file is part of tinyTPU.
-- 
-- tinyTPU is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
-- 
-- tinyTPU is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with tinyTPU. If not, see <http://www.gnu.org/licenses/>.

--! @file ACTIVATION.vhdl
--! @author Jonas Fuhrmann
--! @brief This component calculates the selected activation function for the input array.
--! @details The input is rounded, has some checker logic for ReLU and look-up-tables for the sigmoid function.
--! All functions are quantized.

use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    
entity ACTIVATION is
    generic(
        MATRIX_WIDTH        : natural := 14
    );
    port(
        CLK, RESET          : in  std_logic;
        ENABLE              : in  std_logic;
        
        ACTIVATION_FUNCTION : in  ACTIVATION_BIT_TYPE;
        SIGNED_NOT_UNSIGNED : in  std_logic;
        
        ACTIVATION_INPUT    : in  WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
        ACTIVATION_OUTPUT   : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1)
    );
end entity ACTIVATION;

--! @brief The architecture of the activation component.
architecture BEH of ACTIVATION is
    
    -- SIGMOID Table
    constant SIGMOID_UNSIGNED   : INTEGER_ARRAY_TYPE(0 to 164)  := (128,130,132,134,136,138,140,142,144,146,148,150,152,154,156,157,159,161,163,165,167,169,170,172,174,176,177,179,181,182,184,186,187,189,190,192,193,195,196,198,199,200,202,203,204,206,207,208,209,210,212,213,214,215,216,217,218,219,220,221,222,223,224,225,225,226,227,228,229,229,230,231,232,232,233,234,234,235,235,236,237,237,238,238,239,239,240,240,241,241,241,242,242,243,243,243,244,244,245,245,245,246,246,246,246,247,247,247,248,248,248,248,248,249,249,249,249,250,250,250,250,250,250,251,251,251,251,251,251,252,252,252,252,252,252,252,252,253,253,253,253,253,253,253,253,253,253,253,254,254,254,254,254,254,254,254,254,254,254,254,254,254,254,254,254);
    constant SIGMOID_SIGNED     : INTEGER_ARRAY_TYPE(-88 to 70) := (1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,3,3,3,3,3,4,4,4,4,4,5,5,5,6,6,6,7,7,8,8,9,9,10,10,11,12,12,13,14,14,15,16,17,18,19,20,21,22,23,25,26,27,29,30,31,33,34,36,38,39,41,43,45,46,48,50,52,54,56,58,60,62,64,66,68,70,72,74,76,78,80,82,83,85,87,89,90,92,94,95,97,98,99,101,102,103,105,106,107,108,109,110,111,112,113,114,114,115,116,116,117,118,118,119,119,120,120,121,121,122,122,122,123,123,123,124,124,124,124,124,125,125,125,125,125,126,126,126,126,126,126,126,126);
    
    -- ELU Table (a=0.195) 
    -- More accuracy can be gained if counting from -4 to 1 -> Q3.5 instead of Q4.4 which is currently implemented
    constant ELU_SIGNED      : INTEGER_ARRAY_TYPE(-63 to 15) := (152, 152, 152, 152, 152, 152, 152, 152, 152, 152, 152, 152, 152, 152, 152, 152, 152, 152, 151, 151, 151, 151, 151, 151, 151, 151, 150, 150, 150, 150, 150, 150, 149, 149, 149, 149, 148, 148, 148, 147, 147, 147, 146, 146, 145, 145, 144, 144, 143, 143, 142, 141, 140, 140, 139, 138, 137, 136, 135, 134, 132, 131, 130, 0, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 96, 104, 112, 120);

    -- SELU Table (a=1.67326, l=1.0507) | Q3.5 -> Q2.6 (TODO: Maybe should be 3.5->3.5 -> Wider range in x > 0 but lower precision of x <= 0)
    constant SELU_SIGNED      : INTEGER_ARRAY_TYPE(-115 to 60) := (147, 147, 147, 147, 147, 147, 147, 147, 147, 148, 148, 148, 148, 148, 148, 148, 149, 149, 149, 149, 149, 149, 150, 150, 150, 150, 150, 151, 151, 151, 151, 152, 152, 152, 152, 153, 153, 153, 154, 154, 154, 155, 155, 155, 156, 156, 157, 157, 157, 158, 158, 159, 159, 160, 160, 161, 161, 162, 162, 163, 164, 164, 165, 166, 166, 167, 168, 169, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 184, 185, 186, 188, 189, 190, 192, 193, 195, 197, 198, 200, 202, 204, 206, 208, 210, 212, 214, 216, 218, 221, 223, 226, 228, 231, 234, 237, 240, 243, 246, 249, 253, 0, 2, 4, 6, 8, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 53, 55, 57, 59, 61, 63, 65, 67, 69, 71, 74, 76, 78, 80, 82, 84, 86, 88, 90, 92, 95, 97, 99, 101, 103, 105, 107, 109, 111, 113, 116, 118, 120, 122, 124, 126);
    -- Unsigned SELU could be just a standard RELU even though we have a multiplier l by 1.0507

    constant SOFTSIGN_UNSIGNED  : INTEGER_ARRAY_TYPE(0 to 246) := (0, 8, 15, 22, 28, 35, 40, 46, 51, 56, 61, 65, 70, 74, 78, 82, 85, 89, 92, 95, 98, 101, 104, 107, 110, 112, 115, 117, 119, 122, 124, 126, 128, 130, 132, 134, 136, 137, 139, 141, 142, 144, 145, 147, 148, 150, 151, 152, 154, 155, 156, 157, 158, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 172, 173, 174, 175, 176, 176, 177, 178, 179, 179, 180, 181, 182, 182, 183, 184, 184, 185, 185, 186, 187, 187, 188, 188, 189, 189, 190, 190, 191, 191, 192, 192, 193, 193, 194, 194, 195, 195, 196, 196, 197, 197, 197, 198, 198, 199, 199, 200, 200, 200, 201, 201, 201, 202, 202, 202, 203, 203, 203, 204, 204, 204, 205, 205, 205, 206, 206, 206, 207, 207, 207, 208, 208, 208, 208, 209, 209, 209, 209, 210, 210, 210, 210, 211, 211, 211, 211, 212, 212, 212, 212, 213, 213, 213, 213, 214, 214, 214, 214, 214, 215, 215, 215, 215, 215, 216, 216, 216, 216, 216, 217, 217, 217, 217, 217, 218, 218, 218, 218, 218, 218, 219, 219, 219, 219, 219, 219, 220, 220, 220, 220, 220, 220, 221, 221, 221, 221, 221, 221, 221, 222, 222, 222, 222, 222, 222, 222, 223, 223, 223, 223, 223, 223, 223, 223, 224, 224, 224, 224, 224, 224, 224, 224, 225, 225, 225, 225, 225, 225, 225, 225, 226, 226, 226, 226, 226, 226, 226, 226, 226, 227);
    constant SOFTSIGN_SIGNED    : INTEGER_ARRAY_TYPE(-128 to 110) := (242, 242, 242, 241, 241, 241, 241, 241, 241, 241, 241, 241, 240, 240, 240, 240, 240, 240, 240, 240, 239, 239, 239, 239, 239, 239, 239, 238, 238, 238, 238, 238, 238, 238, 237, 237, 237, 237, 237, 236, 236, 236, 236, 236, 236, 235, 235, 235, 235, 234, 234, 234, 234, 233, 233, 233, 233, 232, 232, 232, 232, 231, 231, 231, 230, 230, 230, 229, 229, 229, 228, 228, 228, 227, 227, 226, 226, 225, 225, 224, 224, 223, 223, 222, 222, 221, 221, 220, 219, 219, 218, 217, 217, 216, 215, 214, 213, 212, 211, 210, 209, 208, 207, 206, 205, 203, 202, 201, 199, 197, 196, 194, 192, 190, 188, 185, 183, 180, 177, 174, 171, 167, 163, 158, 154, 148, 142, 136, 0, 8, 14, 20, 26, 30, 35, 39, 43, 46, 49, 52, 55, 57, 60, 62, 64, 66, 68, 69, 71, 73, 74, 75, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 89, 90, 91, 91, 92, 93, 93, 94, 94, 95, 95, 96, 96, 97, 97, 98, 98, 99, 99, 100, 100, 100, 101, 101, 101, 102, 102, 102, 103, 103, 103, 104, 104, 104, 104, 105, 105, 105, 105, 106, 106, 106, 106, 107, 107, 107, 107, 108, 108, 108, 108, 108, 108, 109, 109, 109, 109, 109, 110, 110, 110, 110, 110, 110, 110, 111, 111, 111, 111, 111, 111, 111, 112);

    constant SOFTPLUS_UNSIGNED: INTEGER_ARRAY_TYPE(0 to 235) := (89, 89, 90, 90, 91, 91, 92, 92, 93, 93, 94, 94, 95, 95, 96, 96, 97, 98, 98, 99, 99, 100, 100, 101, 101, 102, 102, 103, 103, 104, 105, 105, 106, 106, 107, 107, 108, 109, 109, 110, 110, 111, 111, 112, 113, 113, 114, 114, 115, 116, 116, 117, 117, 118, 119, 119, 120, 120, 121, 122, 122, 123, 123, 124, 125, 125, 126, 127, 127, 128, 128, 129, 130, 130, 131, 132, 132, 133, 134, 134, 135, 136, 136, 137, 137, 138, 139, 139, 140, 141, 141, 142, 143, 143, 144, 145, 146, 146, 147, 148, 148, 149, 150, 150, 151, 152, 152, 153, 154, 154, 155, 156, 157, 157, 158, 159, 159, 160, 161, 162, 162, 163, 164, 164, 165, 166, 167, 167, 168, 169, 170, 170, 171, 172, 173, 173, 174, 175, 175, 176, 177, 178, 178, 179, 180, 181, 181, 182, 183, 184, 185, 185, 186, 187, 188, 188, 189, 190, 191, 191, 192, 193, 194, 195, 195, 196, 197, 198, 199, 199, 200, 201, 202, 202, 203, 204, 205, 206, 206, 207, 208, 209, 210, 210, 211, 212, 213, 214, 215, 215, 216, 217, 218, 219, 219, 220, 221, 222, 223, 224, 224, 225, 226, 227, 228, 229, 229, 230, 231, 232, 233, 234, 234, 235, 236, 237, 238, 239, 239, 240, 241, 242, 243, 244, 245, 245, 246, 247, 248, 249, 250, 250, 251, 252, 253, 254);
    constant SOFTPLUS_SIGNED: INTEGER_ARRAY_TYPE(-128 to 18) := (5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 8, 8, 8, 8, 9, 9, 9, 9, 10, 10, 10, 11, 11, 11, 12, 12, 12, 13, 13, 14, 14, 14, 15, 15, 16, 16, 17, 17, 18, 18, 19, 20, 20, 21, 21, 22, 23, 23, 24, 25, 26, 26, 27, 28, 29, 30, 31, 32, 32, 33, 34, 35, 37, 38, 39, 40, 41, 42, 43, 45, 46, 47, 49, 50, 52, 53, 55, 56, 58, 59, 61, 63, 64, 66, 68, 70, 72, 74, 76, 78, 80, 82, 85, 87, 89, 92, 94, 96, 99, 102, 104, 107, 110, 113, 115, 118, 121, 124, 128, 131, 134, 137, 141, 144, 147, 151, 155, 158, 162, 166, 170, 173, 177, 181, 186, 190, 194, 198, 203, 207, 211, 216, 221, 225, 230, 235, 240, 244, 249, 254);

    type SIGMOID_ARRAY_TYPE is array(natural range<>) of std_logic_vector(20 downto 0);
    type SOFTSIGN_ARRAY_TYPE is array(natural range<>) of std_logic_vector(20 downto 0);
    type SOFTPLUS_ARRAY_TYPE is array(natural range<>) of std_logic_vector(20 downto 0);
    type RELU_ARRAY_TYPE is array(natural range<>) of std_logic_vector(3*BYTE_WIDTH-1 downto 0);

    type ELU_ARRAY_TYPE is array(natural range<>) of std_logic_vector(3*BYTE_WIDTH-1 downto 0); -- 24 Bits Q16.8 -> Q4.4 | TODO -> 3.4
    type SELU_ARRAY_TYPE is array(natural range<>) of std_logic_vector(3*BYTE_WIDTH-1 downto 0); -- 24 Bits [Signed: Q16.5 + 3&0 -> Q3.5 || Unsigned: Qu16.8 -> Qu8]
    

    signal INPUT_REG_cs     : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal INPUT_REG_ns     : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    signal INPUT_PIPE0_cs   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal INPUT_PIPE0_ns   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    signal RELU_ROUND_REG_cs    : RELU_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal RELU_ROUND_REG_ns    : RELU_ARRAY_TYPE(0 to MATRIX_WIDTH-1);

    --RELU6
    signal RELU6_ROUND_REG_cs    : RELU_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal RELU6_ROUND_REG_ns    : RELU_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    signal SIGMOID_ROUND_REG_cs : SIGMOID_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal SIGMOID_ROUND_REG_ns : SIGMOID_ARRAY_TYPE(0 to MATRIX_WIDTH-1);

    signal ELU_ROUND_REG_cs : ELU_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal ELU_ROUND_REG_ns : ELU_ARRAY_TYPE(0 to MATRIX_WIDTH-1);

    signal SELU_ROUND_REG_cs : SELU_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal SELU_ROUND_REG_ns : SELU_ARRAY_TYPE(0 to MATRIX_WIDTH-1);

    signal SOFTSIGN_ROUND_REG_cs : SOFTSIGN_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal SOFTSIGN_ROUND_REG_ns : SOFTSIGN_ARRAY_TYPE(0 to MATRIX_WIDTH-1);

    signal SOFTPLUS_ROUND_REG_cs  :  SOFTPLUS_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal SOFTPLUS_ROUND_REG_ns  :  SOFTPLUS_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    signal RELU_OUTPUT      : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    --RELU6
    signal RELU6_OUTPUT     : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);

    signal SIGMOID_OUTPUT   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal ELU_OUTPUT       : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal SELU_OUTPUT      : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    

    --SOFTSIGN
    signal SOFTSIGN_OUTPUT   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);

    --SOFTPLUS
    signal SOFTPLUS_OUTPUT   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);

    signal OUTPUT_REG_cs    : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal OUTPUT_REG_ns    : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    signal ACTIVATION_FUNCTION_REG0_cs  : ACTIVATION_BIT_TYPE := (others => '0');
    signal ACTIVATION_FUNCTION_REG0_ns  : ACTIVATION_BIT_TYPE;
    signal ACTIVATION_FUNCTION_REG1_cs  : ACTIVATION_BIT_TYPE := (others => '0');
    signal ACTIVATION_FUNCTION_REG1_ns  : ACTIVATION_BIT_TYPE;
    
    signal SIGNED_NOT_UNSIGNED_REG_cs   : std_logic_vector(0 to 1) := (others => '0');
    signal SIGNED_NOT_UNSIGNED_REG_ns   : std_logic_vector(0 to 1);
begin

    INPUT_REG_ns    <= ACTIVATION_INPUT;
    
    ROUND:
    process(INPUT_REG_cs, SIGNED_NOT_UNSIGNED_REG_cs(0)) is
    begin
        for i in 0 to MATRIX_WIDTH-1 loop
            INPUT_PIPE0_ns(i)       <= INPUT_REG_cs(i)(4*BYTE_WIDTH-1 downto 3*BYTE_WIDTH);
            -- RELU Round --
            RELU_ROUND_REG_ns(i)    <= std_logic_vector(unsigned(INPUT_REG_cs(i)(4*BYTE_WIDTH-1 downto 1*BYTE_WIDTH)) + INPUT_REG_cs(i)(1*BYTE_WIDTH-1));
            --RELU6
            RELU6_ROUND_REG_ns(i)    <= std_logic_vector(unsigned(INPUT_REG_cs(i)(4*BYTE_WIDTH-1 downto 1*BYTE_WIDTH)) + INPUT_REG_cs(i)(1*BYTE_WIDTH-1));
            
            -- SIGMOID Round --
            if SIGNED_NOT_UNSIGNED_REG_cs(0) = '0' then
                -- unsigned - Qu3.5 table range
                SIGMOID_ROUND_REG_ns(i) <= std_logic_vector(unsigned(INPUT_REG_cs(i)(4*BYTE_WIDTH-1 downto 2*BYTE_WIDTH-5)) + INPUT_REG_cs(i)(2*BYTE_WIDTH-6));
            else
                -- signed - Q4.4 table range
                SIGMOID_ROUND_REG_ns(i) <= std_logic_vector(unsigned(INPUT_REG_cs(i)(4*BYTE_WIDTH-1 downto 2*BYTE_WIDTH-4)) + INPUT_REG_cs(i)(2*BYTE_WIDTH-5)) & '0';
            end if;

            -- ELU Round --
            ELU_ROUND_REG_ns(i)    <= std_logic_vector(unsigned(INPUT_REG_cs(i)(4*BYTE_WIDTH-1 downto 1*BYTE_WIDTH)) + INPUT_REG_cs(i)(1*BYTE_WIDTH-1)); -- 24 Bits Progression

            -- SELU Round --
            if SIGNED_NOT_UNSIGNED_REG_cs(0) = '0' then
                -- unsigned - Qu4.4 table range
                SELU_ROUND_REG_ns(i) <= std_logic_vector(unsigned(INPUT_REG_cs(i)(4*BYTE_WIDTH-1 downto 1*BYTE_WIDTH)) + INPUT_REG_cs(i)(1*BYTE_WIDTH-1));
            else
                -- signed - Q3.5 table range
                SELU_ROUND_REG_ns(i) <= std_logic_vector(unsigned(INPUT_REG_cs(i)(4*BYTE_WIDTH-1 downto 2*BYTE_WIDTH-5)) + INPUT_REG_cs(i)(2*BYTE_WIDTH-6)) & '0' & '0' & '0';
            end if;

            --SOFTSIGN
            if SIGNED_NOT_UNSIGNED_REG_cs(0) = '0' then
                -- unsigned - Qu3.5 table range
                SOFTSIGN_ROUND_REG_ns(i) <= std_logic_vector(unsigned(INPUT_REG_cs(i)(4*BYTE_WIDTH-1 downto 2*BYTE_WIDTH-5)) + INPUT_REG_cs(i)(2*BYTE_WIDTH-6));
            else
                -- signed - Q4.4 table range
                SOFTSIGN_ROUND_REG_ns(i) <= std_logic_vector(unsigned(INPUT_REG_cs(i)(4*BYTE_WIDTH-1 downto 2*BYTE_WIDTH-4)) + INPUT_REG_cs(i)(2*BYTE_WIDTH-5)) & '0';
            end if;
            
            --SOFTPLUS  UNSIGNED Q1.7 -> Q1.7        --SIGNED Q3.5 -> Qu8
            --TODO : CHECK IF THIS IS RIGHT
            if SIGNED_NOT_UNSIGNED_REG_cs(0) = '0' then
                -- unsigned - Q1.7 table range
                SOFTPLUS_ROUND_REG_ns(i) <= std_logic_vector(unsigned(INPUT_REG_cs(i)(4*BYTE_WIDTH-1 downto 2*BYTE_WIDTH-7)) + INPUT_REG_cs(i)(2*BYTE_WIDTH-8));
            else
                -- signed - Q3.5 table range
                SOFTPLUS_ROUND_REG_ns(i) <= std_logic_vector(unsigned(INPUT_REG_cs(i)(4*BYTE_WIDTH-1 downto 2*BYTE_WIDTH-5)) + INPUT_REG_cs(i)(2*BYTE_WIDTH-6));
            end if;

            
        end loop;
    end process ROUND;
    
    ACTIVATION_FUNCTION_REG0_ns <= ACTIVATION_FUNCTION;
    ACTIVATION_FUNCTION_REG1_ns <= ACTIVATION_FUNCTION_REG0_cs;
    
    SIGNED_NOT_UNSIGNED_REG_ns(0) <= SIGNED_NOT_UNSIGNED;
    SIGNED_NOT_UNSIGNED_REG_ns(1) <= SIGNED_NOT_UNSIGNED_REG_cs(0);
    
    RELU_ACTIVATION:
    process(SIGNED_NOT_UNSIGNED_REG_cs(1), RELU_ROUND_REG_cs) is
        variable SIGNED_NOT_UNSIGNED_v  : std_logic;
        variable RELU_ROUND_v           : RELU_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
        
        variable RELU_OUTPUT_v          : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    begin
        SIGNED_NOT_UNSIGNED_v   := SIGNED_NOT_UNSIGNED_REG_cs(1);
        RELU_ROUND_v            := RELU_ROUND_REG_cs;
        
        for i in 0 to MATRIX_WIDTH-1 loop
            if SIGNED_NOT_UNSIGNED_v = '1' then
                if    signed(RELU_ROUND_v(i)) <   0 then
                    RELU_OUTPUT_v(i) := (others => '0');
                elsif signed(RELU_ROUND_v(i)) > 127 then -- Bounded ReLU
                    RELU_OUTPUT_v(i) := std_logic_vector(to_signed(127, BYTE_WIDTH));
                else
                    RELU_OUTPUT_v(i) := RELU_ROUND_v(i)(BYTE_WIDTH-1 downto 0);
                end if;
            else
                if  unsigned(RELU_ROUND_v(i)) > 255 then -- Bounded ReLU
                    RELU_OUTPUT_v(i) := std_logic_vector(to_unsigned(255, BYTE_WIDTH));
                else
                    RELU_OUTPUT_v(i) := RELU_ROUND_v(i)(BYTE_WIDTH-1 downto 0);
                end if;
            end if;
        end loop;
        
        RELU_OUTPUT <= RELU_OUTPUT_v;
    end process RELU_ACTIVATION;
  
    --RELU6 ACTIVATION PROCESS
    RELU6_ACTIVATION:
    process(SIGNED_NOT_UNSIGNED_REG_cs(1), RELU6_ROUND_REG_cs) is
        variable SIGNED_NOT_UNSIGNED_v  : std_logic;
        variable RELU6_ROUND_v           : RELU_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
        
        variable RELU6_OUTPUT_v          : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    begin
        SIGNED_NOT_UNSIGNED_v   := SIGNED_NOT_UNSIGNED_REG_cs(1);
        RELU6_ROUND_v            := RELU6_ROUND_REG_cs;
        
        for i in 0 to MATRIX_WIDTH-1 loop
            if SIGNED_NOT_UNSIGNED_v = '1' then
                if    signed(RELU6_ROUND_v(i)) <   0 then
                    RELU6_OUTPUT_v(i) := (others => '0');
                elsif signed(RELU6_ROUND_v(i)) > 127 then -- Bounded ReLU6
                    RELU6_OUTPUT_v(i) := std_logic_vector(to_signed(127, BYTE_WIDTH));
                else
                    RELU6_OUTPUT_v(i) := RELU6_ROUND_v(i)(BYTE_WIDTH-1 downto 0);
                end if;
            else
                if  unsigned(RELU6_ROUND_v(i)) > 255 then -- Bounded ReLU6
                    RELU6_OUTPUT_v(i) := std_logic_vector(to_unsigned(255, BYTE_WIDTH));
                else
                    RELU6_OUTPUT_v(i) := RELU6_ROUND_v(i)(BYTE_WIDTH-1 downto 0);
                end if;
            end if;
        end loop;
        
        RELU6_OUTPUT <= RELU6_OUTPUT_v;
    end process RELU6_ACTIVATION;
    
    ELU_ACTIVATION:
    process(SIGNED_NOT_UNSIGNED_REG_cs(1), ELU_ROUND_REG_cs) is
        variable SIGNED_NOT_UNSIGNED_v  : std_logic;
        
        variable ELU_ROUND_v           : ELU_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
        variable ELU_OUTPUT_v          : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    begin
        SIGNED_NOT_UNSIGNED_v   := SIGNED_NOT_UNSIGNED_REG_cs(1);
        ELU_ROUND_v             := ELU_ROUND_REG_cs;
        
            if SIGNED_NOT_UNSIGNED_v = '1' then
        for i in 0 to MATRIX_WIDTH-1 loop
                -- Q4.4
                if    signed(ELU_ROUND_v(i)(3*BYTE_WIDTH-1 downto 1*BYTE_WIDTH)) <= -4 then -- Bounded ELU (0.195)
                    ELU_OUTPUT_v(i) := std_logic_vector(to_unsigned(153, BYTE_WIDTH));
                elsif signed(ELU_ROUND_v(i)(3*BYTE_WIDTH-1 downto 1*BYTE_WIDTH)) >= 1 then -- Bounded ELU (~1)
                    ELU_OUTPUT_v(i) := std_logic_vector(to_unsigned(127, BYTE_WIDTH));
                else -- Bounded ELU (0.195) & RELU (0 <= x < 1)
                    ELU_OUTPUT_v(i) := std_logic_vector(to_unsigned(ELU_SIGNED(to_integer(signed(ELU_ROUND_v(i)(2*BYTE_WIDTH-5 downto 1*BYTE_WIDTH-4)))), BYTE_WIDTH));
                end if;
            else
                -- ELU Behaves exactly like RELU if unsigned 
                if  unsigned(ELU_ROUND_v(i)) > 255 then -- Bounded ELU
                    ELU_OUTPUT_v(i) := std_logic_vector(to_unsigned(255, BYTE_WIDTH));
                else
                    ELU_OUTPUT_v(i) := ELU_ROUND_v(i)(BYTE_WIDTH-1 downto 0);
                end if;
            end if;
        end loop;
        
        ELU_OUTPUT <= ELU_OUTPUT_v;
    end process ELU_ACTIVATION;

    SELU_ACTIVATION:
    process(SIGNED_NOT_UNSIGNED_REG_cs(1), SELU_ROUND_REG_cs) is
        variable SIGNED_NOT_UNSIGNED_v  : std_logic;
        variable SELU_ROUND_v           : SELU_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
        
        variable SELU_OUTPUT_v          : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    begin
        SIGNED_NOT_UNSIGNED_v   := SIGNED_NOT_UNSIGNED_REG_cs(1);
        SELU_ROUND_v            := SELU_ROUND_REG_cs;
        
        for i in 0 to MATRIX_WIDTH-1 loop
            if SIGNED_NOT_UNSIGNED_v = '1' then
                -- Q3.5 -> Q2.6
                if signed(SELU_ROUND_v(i)(23 downto 3)) < -115 then -- Bounded SELU (-1.7188 -> 146)
                    SELU_OUTPUT_v(i) := std_logic_vector(to_unsigned(146, BYTE_WIDTH));
                elsif signed(SELU_ROUND_v(i)(23 downto 3)) > 60 then -- Bounded SELU (+1.9844, 127)
                    SELU_OUTPUT_v(i) := std_logic_vector(to_unsigned(127, BYTE_WIDTH));
                else 
                    SELU_OUTPUT_v(i) := std_logic_vector(to_unsigned(SELU_SIGNED(to_integer(signed(SELU_ROUND_v(i)(23 downto 3)))), BYTE_WIDTH));
                end if;
            else
                -- TODO: Q4.4 - SELU Behaves similarly to RELU when unsigned, just multiplied by a factor of 'l'.
                    SELU_OUTPUT_v(i) := std_logic_vector(to_unsigned(255, BYTE_WIDTH));
                if  unsigned(SELU_ROUND_v(i)) > 255 then -- Bounded SELU
                else
                    SELU_OUTPUT_v(i) := SELU_ROUND_v(i)(BYTE_WIDTH-1 downto 0);
                end if;
            end if;
        end loop;
        
        SELU_OUTPUT <= SELU_OUTPUT_v;
    end process SELU_ACTIVATION;

    SIGMOID_ACTIVATION:
    process(SIGNED_NOT_UNSIGNED_REG_cs(1), SIGMOID_ROUND_REG_cs) is
        variable SIGNED_NOT_UNSIGNED_v  : std_logic;
        variable SIGMOID_ROUND_v        : SIGMOID_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
        
        variable SIGMOID_OUTPUT_v       : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    begin
        SIGNED_NOT_UNSIGNED_v   := SIGNED_NOT_UNSIGNED_REG_cs(1);
        SIGMOID_ROUND_v         := SIGMOID_ROUND_REG_cs;
        
        for i in 0 to MATRIX_WIDTH-1 loop
            if SIGNED_NOT_UNSIGNED_v = '1' then -- Signed
                if signed(SIGMOID_ROUND_v(i)(20 downto 1)) < -88 then
                    SIGMOID_OUTPUT_v(i) := (others => '0');
                elsif signed(SIGMOID_ROUND_v(i)(20 downto 1)) > 70 then
                    SIGMOID_OUTPUT_v(i) := std_logic_vector(to_signed(127, BYTE_WIDTH));
                else
                    SIGMOID_OUTPUT_v(i) := std_logic_vector(to_signed(SIGMOID_SIGNED(to_integer(signed(SIGMOID_ROUND_v(i)(20 downto 1)))), BYTE_WIDTH));
                end if;
            else    -- Unsigned
                if unsigned(SIGMOID_ROUND_v(i)) > 164 then
                    SIGMOID_OUTPUT_v(i) := std_logic_vector(to_unsigned(255, BYTE_WIDTH));
                else
                    SIGMOID_OUTPUT_v(i) := std_logic_vector(to_unsigned(SIGMOID_UNSIGNED(to_integer(unsigned(SIGMOID_ROUND_v(i)))), BYTE_WIDTH));
                end if;
            end if;
        end loop;
        
        SIGMOID_OUTPUT <= SIGMOID_OUTPUT_v;
    end process SIGMOID_ACTIVATION;

    --SOFTSIGN ACTIVATION PROCESS
    SOFTSIGN_ACTIVATION:
    process(SIGNED_NOT_UNSIGNED_REG_cs(1), SOFTSIGN_ROUND_REG_cs) is
        variable SIGNED_NOT_UNSIGNED_v   : std_logic;
        variable SOFTSIGN_ROUND_v        : SOFTSIGN_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
        
        variable SOFTSIGN_OUTPUT_v       : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    begin
        SIGNED_NOT_UNSIGNED_v   := SIGNED_NOT_UNSIGNED_REG_cs(1);
        SOFTSIGN_ROUND_v         := SOFTSIGN_ROUND_REG_cs;
        
        for i in 0 to MATRIX_WIDTH-1 loop
            if SIGNED_NOT_UNSIGNED_v = '1' then -- Signed
                if signed(SOFTSIGN_ROUND_v(i)(20 downto 1)) < -128 then
                    SOFTSIGN_OUTPUT_v(i) := (others => '0');
                elsif signed(SOFTSIGN_ROUND_v(i)(20 downto 1)) > 110 then
                    SOFTSIGN_OUTPUT_v(i) := std_logic_vector(to_signed(122, BYTE_WIDTH));
                else
                    SOFTSIGN_OUTPUT_v(i) := std_logic_vector(to_signed(SOFTSIGN_SIGNED(to_integer(signed(SOFTSIGN_ROUND_v(i)(20 downto 1)))), BYTE_WIDTH));
                end if;
            else    -- Unsigned
                if unsigned(SOFTSIGN_ROUND_v(i)) > 246 then
                    SOFTSIGN_OUTPUT_v(i) := std_logic_vector(to_unsigned(227, BYTE_WIDTH));
                else
                    SOFTSIGN_OUTPUT_v(i) := std_logic_vector(to_unsigned(SOFTSIGN_UNSIGNED(to_integer(unsigned(SOFTSIGN_ROUND_v(i)))), BYTE_WIDTH));
                end if;
            end if;
        end loop;
        
        SOFTSIGN_OUTPUT <= SOFTSIGN_OUTPUT_v;
    end process SOFTSIGN_ACTIVATION;
    
    SOFTPLUS_ACTIVATION:    -- UNSIGNED Q1.7 -> Q1.7        --SIGNED Q3.5 -> Qu8
    process(SIGNED_NOT_UNSIGNED_REG_cs(1), SOFTPLUS_ROUND_REG_cs) is 
        variable SIGNED_NOT_UNSIGNED_v   : std_logic;
        variable SOFTPLUS_ROUND_v        : SOFTPLUS_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
        variable SOFTPLUS_OUTPUT_v       : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    begin
        SIGNED_NOT_UNSIGNED_v   := SIGNED_NOT_UNSIGNED_REG_cs(1);
        SOFTPLUS_ROUND_v         := SOFTPLUS_ROUND_REG_cs;
    
        for i in 0 to MATRIX_WIDTH-1 loop
            if SIGNED_NOT_UNSIGNED_v = '1' then -- Signed
                if signed(SOFTPLUS_ROUND_v(i)(20 downto 1)) <  -128 then
                    SOFTSIGN_OUTPUT_v(i) := (others => '0');
                elsif signed(SOFTPLUS_ROUND_v(i)(20 downto 1)) > 18 then
                    SOFTPLUS_OUTPUT_v(i) := std_logic_vector(to_signed(255, BYTE_WIDTH));
                else
                    SOFTPLUS_OUTPUT_v(i) := std_logic_vector(to_signed(SOFTPLUS_SIGNED(to_integer(signed(SOFTPLUS_ROUND_v(i)(20 downto 1)))), BYTE_WIDTH));
                end if;
            else    -- Unsigned
                if unsigned(SOFTPLUS_ROUND_v(i)) > 235 then
                    SOFTPLUS_OUTPUT_v(i) := std_logic_vector(to_unsigned(255, BYTE_WIDTH));
                else
                    SOFTPLUS_OUTPUT_v(i) := std_logic_vector(to_unsigned(SOFTPLUS_UNSIGNED(to_integer(unsigned(SOFTPLUS_ROUND_v(i)))), BYTE_WIDTH));
                end if;
            end if;
        end loop;
    
        SOFTPLUS_OUTPUT <= SOFTPLUS_OUTPUT_v;
    end process SOFTPLUS_ACTIVATION;
    
    CHOOSE_ACTIVATION:
    process(ACTIVATION_FUNCTION_REG1_cs, RELU_OUTPUT, SIGMOID_OUTPUT, RELU6_OUTPUT, SOFTSIGN_OUTPUT, ,INPUT_PIPE0_cs) is
        variable ACTIVATION_FUNCTION_v  : ACTIVATION_BIT_TYPE;
        variable RELU_OUTPUT_v          : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
        variable SIGMOID_OUTPUT_v       : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
        variable ELU_OUTPUT_v           : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
        variable SELU_OUTPUT_v          : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
        variable ACTIVATION_INPUT_v     : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
        
        variable OUTPUT_REG_ns_v        : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    begin
        ACTIVATION_FUNCTION_v   := ACTIVATION_FUNCTION_REG1_cs;
        RELU_OUTPUT_v           := RELU_OUTPUT;
        SIGMOID_OUTPUT_v        := SIGMOID_OUTPUT;
        ELU_OUTPUT_v            := ELU_OUTPUT;
        SELU_OUTPUT_v           := SELU_OUTPUT;
        ACTIVATION_INPUT_v      := INPUT_PIPE0_cs;
        for i in 0 to MATRIX_WIDTH-1 loop            
            case BITS_TO_ACTIVATION(ACTIVATION_FUNCTION_v) is
                when RELU => OUTPUT_REG_ns_v(i) := RELU_OUTPUT_v(i);
                when SIGMOID => OUTPUT_REG_ns_v(i) := SIGMOID_OUTPUT_v(i);
                when ELU => OUTPUT_REG_ns_v(i) := ELU_OUTPUT_v(i);
                when SELU => OUTPUT_REG_ns_v(i) := SELU_OUTPUT_v(i);
                when NO_ACTIVATION => OUTPUT_REG_ns_v(i) := ACTIVATION_INPUT_v(i);
                when others => 
                    report "Unknown activation function!" severity ERROR;
                    OUTPUT_REG_ns_v(i) := ACTIVATION_INPUT_v(i);
            end case;
        end loop;
        
        OUTPUT_REG_ns <= OUTPUT_REG_ns_v;
    end process CHOOSE_ACTIVATION;
    
    ACTIVATION_OUTPUT <= OUTPUT_REG_cs;
    
    SEQ_LOG:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if RESET = '1' then
                OUTPUT_REG_cs   <= (others => (others => '0'));
                INPUT_REG_cs    <= (others => (others => '0'));
                INPUT_PIPE0_cs  <= (others => (others => '0'));
                RELU_ROUND_REG_cs   <= (others => (others => '0'));
                SIGMOID_ROUND_REG_cs<= (others => (others => '0'));
                ELU_ROUND_REG_cs    <= (others => (others => '0'));
                SELU_ROUND_REG_cs   <= (others => (others => '0'));
                SIGNED_NOT_UNSIGNED_REG_cs  <= (others => '0');
                ACTIVATION_FUNCTION_REG0_cs <= (others => '0');
                ACTIVATION_FUNCTION_REG1_cs <= (others => '0');
            else
                if ENABLE = '1' then
                    OUTPUT_REG_cs   <= OUTPUT_REG_ns;
                    INPUT_REG_cs    <= INPUT_REG_ns;
                    INPUT_PIPE0_cs  <= INPUT_PIPE0_ns;
                    RELU_ROUND_REG_cs   <= RELU_ROUND_REG_ns;
                    SIGMOID_ROUND_REG_cs<= SIGMOID_ROUND_REG_ns;
                    ELU_ROUND_REG_cs <= ELU_ROUND_REG_ns;
                    SELU_ROUND_REG_cs <= SELU_ROUND_REG_ns;
                    SIGNED_NOT_UNSIGNED_REG_cs  <= SIGNED_NOT_UNSIGNED_REG_ns;
                    ACTIVATION_FUNCTION_REG0_cs <= ACTIVATION_FUNCTION_REG0_ns;
                    ACTIVATION_FUNCTION_REG1_cs <= ACTIVATION_FUNCTION_REG1_ns;
                end if;
            end if;
        end if;
    end process SEQ_LOG;
    
end architecture BEH;