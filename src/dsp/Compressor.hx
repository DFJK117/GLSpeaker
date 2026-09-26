package dsp;

import haxe.io.Float32Array;

/**
 * 单边带动态压缩器（作用于"分析信号"，即喂给可视化 RMS/FFT 的数据）。
 * 与原 App 的 Pcm$Compressor 对应：阈值以下线性通过，以上按比率压缩。
 */
class Compressor {

	/** dBFS 阈值，如 -18.0 */
	public var thresholdDb:Float;
	/** 压缩比，如 4.0 */
	public var ratio:Float;
	/** 起音时间（秒），一阶平滑 */
	public var attack:Float;
	/** 释放时间（秒） */
	public var release:Float;

	var envelope:Float;

	public function new(thresholdDb:Float = -18.0, ratio:Float = 4.0, attack:Float = 0.005, release:Float = 0.15) {
		this.thresholdDb = thresholdDb;
		this.ratio = ratio;
		this.attack = attack;
		this.release = release;
		envelope = 0;
	}

	static inline var LN10:Float = 2.302585092994046; // Haxe std 无该常量，硬编码

	static inline function toDb(x:Float):Float {
		// Haxe std 无 log10，换底实现；x 过小时钳制
		return 20.0 * Math.log(x <= 1e-9 ? 1e-9 : x) / LN10;
	}

	static inline function fromDb(db:Float):Float {
		return Math.exp(db * LN10 / 20.0); // 10^(db/20)
	}

	/** 处理一帧采样（in place），返回本块平均增益（dB），供可视化参考 */
	public function process(samples:Float32Array, sampleRate:Float):Float {
		var n = samples.length;
		if (n == 0) return 0;
		var aCoef = Math.exp(-1.0 / (attack * sampleRate));
		var rCoef = Math.exp(-1.0 / (release * sampleRate));
		var gainSum = 0.0;
		var thr = fromDb(thresholdDb);
		for (i in 0...n) {
			var x = samples[i];
			if (x < 0) x = -x;
			// 包络
			var c = x > envelope ? aCoef : rCoef;
			envelope = c * envelope + (1 - c) * x;
			// 增益计算
			var g = 1.0;
			if (envelope > thr && ratio > 1.0) {
				var overDb = toDb(envelope) - thresholdDb;
				g = fromDb(-overDb * (1.0 - 1.0 / ratio));
			}
			gainSum += g;
			samples[i] = samples[i] * g;
		}
		return gainSum / n;
	}
}
