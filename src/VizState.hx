package;

import haxe.io.Float32Array;

/**
 * 全局共享状态：UI(压缩器面板) / 音频引擎 / GL 渲染器 三方共读共写。
 */
class VizState {

	public static inline var BINS:Int = 64;       // 频谱柱数量（圆形排布）
	public static inline var FFT_SIZE:Int = 4096; // FFT 窗口

	/** 增益倍率（作用于分析信号/可视化） */
	public var gain:Float = 1.5;
	/** 仅增益图形不增益音频：ON 时增益只影响可视化，不影响播放音量 */
	public var graphicsOnlyGain:Bool = true;
	/** 压缩器阈值 dBFS */
	public var thresholdDb:Float = -18.0;
	/** 压缩器比率 */
	public var ratio:Float = 4.0;

	public var playing:Bool = false;
	public var fileName:String = "(未加载)";

	// —— 以下由音频引擎每帧写入，渲染器读取 ——
	/** 瞬时 RMS (0..~1，已过压缩器+增益) */
	public var rms:Float = 0;
	/** 低通平滑 RMS（对应原版 RMSLPFL，驱动果冻缩放/喇叭鼓动） */
	public var rmsSmooth:Float = 0;
	/** 频谱幅度谱 (BINS 个，已归一化 0..~1) */
	public var spectrum:Float32Array;
	/** 主频 Hz */
	public var maxFreq:Float = 0;
	/** 采样率 */
	public var sampleRate:Float = 44100;

	public function new() {
		spectrum = new Float32Array(BINS);
	}

	/** UI 变更后同步到压缩器 */
	public function applyTo(c:dsp.Compressor):Void {
		c.thresholdDb = thresholdDb;
		c.ratio = ratio;
	}
}
