package tests;

import dsp.Compressor;
import dsp.FFT;
import haxe.io.Float32Array;

/**
 * 纯 DSP 单元测试（haxe --interp 直接跑，无需任何运行时）。
 */
class TestMain {

	static var passed = 0;
	static var failed = 0;

	public static function main() {
		testFFT();
		testFFTMagnitudes();
		testCompressor();
		trace('==========================================');
		trace('PASSED: $passed   FAILED: $failed');
		if (failed > 0) {
			trace('!!! TESTS FAILED !!!');
			Sys.exit(1);
		} else {
			trace('ALL TESTS OK');
		}
	}

	static function check(name:String, cond:Bool, detail:String = "") {
		if (cond) {
			passed++;
			trace('  [OK]   $name');
		} else {
			failed++;
			trace('  [FAIL] $name  $detail');
		}
	}

	static function near(a:Float, b:Float, eps:Float):Bool {
		return Math.abs(a - b) <= eps;
	}

	// 纯直流信号 → 只有 0 频 bin 有值
	static function testFFT() {
		var n = 1024;
		var fft = new FFT(n);
		var re = new Float32Array(n);
		var im = new Float32Array(n);
		for (i in 0...n) re[i] = 1.0;
		fft.run(re, im);
		var ok = true;
		for (k in 1...n) {
			if (Math.abs(re[k]) > 1e-3 || Math.abs(im[k]) > 1e-3) { ok = false; break; }
		}
		check("FFT: 直流信号只有 bin0", ok, 'bin0=' + re[0]);
		check("FFT: bin0 幅度 = n", near(re[0], n, 1e-2), 're[0]=' + re[0]);
	}

	// 单频正弦 → 对应 bin 出峰
	static function testFFTMagnitudes() {
		var n = 1024;
		var fft = new FFT(n);
		var buf = new Float32Array(n);
		var freq = 64; // bin 64
		for (i in 0...n) buf[i] = Math.sin(2 * Math.PI * freq * i / n);
		var mag = new Float32Array(n >> 1);
		fft.magnitude(buf, mag);
		var peakBin = 0;
		var peakVal = -1.0;
		for (i in 1...(mag.length)) {
			if (mag[i] > peakVal) { peakVal = mag[i]; peakBin = i; }
		}
		check("FFT: 64bin 正弦峰值位置正确", peakBin == freq, 'peak=$peakBin');
		// 单边幅度谱: |X[k0]| = A*N/2，换算 A = 2|X[k0]|/N = 1.0
		check("FFT: 峰值幅度 ~1.0", near(peakVal, 1.0, 0.02), 'val=$peakVal');
	}

	static function testCompressor() {
		var c = new Compressor(-12.0, 4.0, 0.005, 0.05);
		var n = 4410; // 0.1s
		var buf = new Float32Array(n);
		for (i in 0...n) buf[i] = 0.9; // 远高于阈值
		var avgGain = c.process(buf, 44100);
		check("压缩器: 高电平被压", avgGain < 0.9, 'gain=$avgGain');
		// 低于阈值 → 基本不压
		var c2 = new Compressor(-12.0, 4.0, 0.005, 0.05);
		for (i in 0...n) buf[i] = 0.1;
		var g2 = c2.process(buf, 44100);
		check("压缩器: 低电平直通", g2 > 0.99, 'gain=$g2');
	}
}
