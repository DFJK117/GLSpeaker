package dsp;

import haxe.io.Float32Array;
import haxe.io.UInt32Array;

/**
 * 迭代式 Radix-2 FFT（纯 Haxe，无依赖）。
 * 输入/输出均为 Float32Array，实部/虚部分离，便于跨线程复用缓冲。
 * length 必须为 2 的幂。
 */
class FFT {

	public var size(default, null):Int;
	var cosTable:Float32Array;
	var sinTable:Float32Array;
	var revTable:UInt32Array;

	public function new(size:Int) {
		if (size <= 0 || (size & (size - 1)) != 0) {
			throw "FFT size must be a power of 2";
		}
		this.size = size;
		cosTable = new Float32Array(size >> 1);
		sinTable = new Float32Array(size >> 1);
		for (i in 0...(size >> 1)) {
			var a = -2.0 * Math.PI * i / size;
			cosTable[i] = Math.cos(a);
			sinTable[i] = Math.sin(a);
		}
		revTable = new UInt32Array(size);
		var bits = log2(size);
		for (i in 0...size) {
			var r = 0;
			var x = i;
			for (b in 0...bits) {
				r = (r << 1) | (x & 1);
				x >>= 1;
			}
			revTable[i] = r;
		}
	}

	public static inline function log2(v:Int):Int {
		var r = 0;
		while (v > 1) { v >>= 1; r++; }
		return r;
	}

	/**
	 * 原地 FFT。re/im 为实部/虚部，长度必须等于 size。
	 */
	public function run(re:Float32Array, im:Float32Array):Void {
		var n = size;
		// 位反转重排
		for (i in 0...n) {
			var j = revTable[i];
			if (j > i) {
				var t = re[i]; re[i] = re[j]; re[j] = t;
				t = im[i]; im[i] = im[j]; im[j] = t;
			}
		}
		// 蝶形
		var half = n >> 1;
		var len = 2;
		while (len <= n) {
			var step = n >> log2(len);
			// step = half / (len>>1)
			step = half >> (log2(len) - 1);
			var i = 0;
			while (i < n) {
				var k = 0;
				for (j in 0...(len >> 1)) {
					var l = i + j;
					var r = l + (len >> 1);
					var c = cosTable[k];
					var s = sinTable[k];
					var tre = re[r] * c - im[r] * s;
					var tim = re[r] * s + im[r] * c;
					re[r] = re[l] - tre;
					im[r] = im[l] - tim;
					re[l] += tre;
					im[l] += tim;
					k += step;
				}
				i += len;
			}
			len <<= 1;
		}
	}

	/**
	 * 对实信号做 FFT，直接输出幅度谱（0..size/2 个 bin）。
	 * out.len 必须为 size/2。
	 */
	public function magnitude(re:Float32Array, out:Float32Array):Void {
		var im = scratchIm;
		if (im == null || im.length != size) im = scratchIm = new Float32Array(size);
		for (i in 0...size) im[i] = 0;
		run(re, im);
		var bins = size >> 1;
		var norm = 2.0 / size;
		for (i in 0...bins) {
			var re2 = re[i] * re[i];
			var im2 = im[i] * im[i];
			out[i] = Math.sqrt(re2 + im2) * norm;
		}
	}

	static var scratchIm:Float32Array = null;
}
