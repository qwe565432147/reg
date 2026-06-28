`ifndef __CIB_FT_REG_DEF_V__
`define __CIB_FT_REG_DEF_V__

// ============================================================================
// cib_ft 寄存器映射  (基地址 = 0x1C00)
// ============================================================================
`define REG_CLK_MODULE_FOD_CTRL       16'h0000       // 时钟频偏检测控制寄存器              (RW)
`define REG_CLK_MODULE_FREQ_ACT_H     16'h0001       // 频率实际值高16位寄存器                    (RO)
`define REG_CLK_MODULE_FREQ_ACT_L    16'h0002       // 频率实际值低16位寄存器                (RW)
`define REG_CLK_MODULE_FREQ_MAX_H         16'h0003       // 频率最大值高16位寄存器               (RO)
`define REG_CLK_MODULE_FREQ_MAX_L         16'h0004       // 频率最大值低16位寄存器                     (RW)
`define REG_CLK_MODULE_FREQ_MIN_H         16'h0005       // 频率最小值高16位寄存器               (RO)
`define REG_CLK_MODULE_FREQ_MIN_L         16'h0006       // 频率最小值低16位寄存器                     (RW)
`define REG_LGC_RSRC_CHK_RESULT             16'h0008       // 资源全检结果寄存器               (RO)

