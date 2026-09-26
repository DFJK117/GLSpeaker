package audio;

import dsp.Compressor;
import dsp.FFT;
import haxe.io.Float32Array;
import lime.media.AudioBuffer;
import lime.media.AudioSource;

/**
 * 音频引擎（Lime 原生音频）：
 *   桌面(cpp): AudioBuffer.fromFile 同步解码 → 整曲转单声道 Float32 → 后台线程 FFT/压缩
 *   Web(html5): decodeAudioData → getChannelData(0)
 *   未加载文件时运行"演示信号"（扫频+节拍包络），保证可视化始终有数据。
 *
 * 增益模型（对应"仅增益图形不增益音频"开关）:
 *   graphicsOnlyGain = true  → 增益只乘分析信号，播放 gain 恒 1
 *   graphicsOnlyGain = false → 增益同时作用播放音量
 */
class AudioEngine {

	public var state:VizState;
	public var compressor(default, null):Compressor;

	var fft:FFT;
	var chunk:Float32Array;
	var mag:Float32Array;
	var binSums:Float32Array;

	// 桌面整曲 PCM
	var mono:Float32Array;
	var totalSamples:Int = 0;
	var bufferRef:AudioBuffer;
	var source:AudioSource;
	var playOffset:Int = 0;      // 暂停位置（样本）
	var stampStart:Float = 0;    // 本次 play 起始时间

	// 歌单（exe 同级 music 文件夹）
	public var playlist:Array<String> = [];
	public var playlistIndex:Int = -1;

	#if sys
	var worker:sys.thread.Thread;
	var mutex:sys.thread.Mutex;
	var queue:Array<Float32Array>;
	var workerRms:Float = 0;
	var workerPeak:Int = 0;
	var workerMag:Float32Array;
	var running:Bool = true;
	#end

	#if js
	var webCtx:js.html.audio.AudioContext;
	var webGain:js.html.audio.GainNode;
	var webSource:js.html.audio.AudioBufferSourceNode;
	var webBuffer:js.html.audio.AudioBuffer;
	var webData:js.html.Float32Array;
	var webStartCtxTime:Float = 0;
	var webOffset:Float = 0;
	#end

	public function new(state:VizState) {
		this.state = state;
		compressor = new Compressor(state.thresholdDb, state.ratio);
		fft = new FFT(VizState.FFT_SIZE);
		chunk = new Float32Array(VizState.FFT_SIZE);
		mag = new Float32Array(VizState.FFT_SIZE >> 1);
		binSums = new Float32Array(state.spectrum.length);
		#if sys
		mutex = new sys.thread.Mutex();
		queue = [];
		workerMag = new Float32Array(state.spectrum.length);
		worker = sys.thread.Thread.create(workerLoop);
		#end
	}

	public function dispose():Void {
		#if sys
		running = false;
		#end
		pause();
	}

	// ——————————————————————————————
	// 桌面：加载/播放
	// ——————————————————————————————
	#if sys
	public function loadFile(path:String):Void {
		pause();
		var buf = AudioBuffer.fromFile(path);
		if (buf == null || buf.data == null) {
			trace('解码失败: $path');
			return;
		}
		bufferRef = buf;
		state.sampleRate = buf.sampleRate;
		var ch = buf.channels > 0 ? buf.channels : 1;
		var bytesPerFrame = Std.int(2 * ch); // 16bit
		var frames = Std.int(buf.data.length / bytesPerFrame);
		mono = new Float32Array(frames);
		for (i in 0...frames) {
			var sum = 0.0;
			for (c in 0...ch) {
				var o = i * bytesPerFrame + c * 2;
				var s = buf.data[o] | (buf.data[o + 1] << 8);
				if (s >= 32768) s -= 65536;
				sum += s / 32768.0;
			}
			mono[i] = sum / ch;
		}
		totalSamples = frames;
		playOffset = 0;
		state.fileName = path.split("\\").pop().split("/").pop();
		trace('已加载: ${state.fileName}  ${Math.round(frames / buf.sampleRate)}s  ${buf.sampleRate}Hz  ${ch}ch');
	}

	public function scanMusicFolder():Void {
		var dir = Sys.getCwd() + "music";
		playlist = [];
		try {
			for (f in sys.FileSystem.readDirectory(dir)) {
				var low = f.toLowerCase();
				if (low.endsWith(".mp3") || low.endsWith(".ogg") || low.endsWith(".wav") || low.endsWith(".flac")) {
					playlist.push(dir + "/" + f);
				}
			}
		} catch (e:Dynamic) {}
		playlist.sort(function(a, b) return Reflect.compare(a, b));
		if (playlist.length > 0) {
			playlistIndex = 0;
			loadFile(playlist[0]);
		}
	}

	public function next(delta:Int):Void {
		if (playlist.length == 0) return;
		playlistIndex = (playlistIndex + delta + playlist.length) % playlist.length;
		loadFile(playlist[playlistIndex]);
		play();
	}

	public function browse():Void {
		Sys.println("把音频文件拖到 GLSpeaker.exe 图标上，或放入 exe 同级 music/ 文件夹后按 ←/→ 切歌。");
		Sys.println("也可以直接输入音频文件完整路径后回车：");
		try {
			var line = Sys.stdin().readLine();
			line = StringTools.trim(StringTools.replace(line, '"', ""));
			if (line.length > 0 && sys.FileSystem.exists(line)) loadFile(line);
		} catch (e:Dynamic) {}
	}

	function positionSamples():Int {
		if (!state.playing) return playOffset;
		var elapsed = haxe.Timer.stamp() - stampStart;
		var pos = playOffset + Std.int(elapsed * state.sampleRate);
		if (pos >= totalSamples) pos = pos % totalSamples; // 循环
		return pos;
	}

	public function play():Void {
		if (mono == null || state.playing) return;
		source = new AudioSource(bufferRef);
		source.gain = state.graphicsOnlyGain ? 1.0 : Math.min(1.0, state.gain * 0.5);
		source.play();
		stampStart = haxe.Timer.stamp();
		state.playing = true;
	}

	public function pause():Void {
		playOffset = state.playing ? positionSamples() : playOffset;
		if (source != null) { source.stop(); source = null; }
		state.playing = false;
	}

	public function applyVolume():Void {
		if (source != null) {
			source.gain = state.graphicsOnlyGain ? 1.0 : Math.min(1.0, state.gain * 0.5);
		}
	}

	public function update():Void {
		if (mono != null) {
			var start = positionSamples();
			var n = chunk.length;
			for (i in 0...n) {
				var idx = start + i;
				chunk[i] = idx < totalSamples ? mono[idx] : 0;
			}
		} else {
			demoSignal();
		}
		enqueueAnalyze();
	}

	function enqueueAnalyze():Void {
		mutex.acquire();
		queue.push(chunk.copy());
		if (queue.length > 3) queue.shift();
		mutex.release();
	}

	function workerLoop():Void {
		while (running) {
			var job:Float32Array = null;
			mutex.acquire();
			if (queue.length > 0) job = queue.shift();
			mutex.release();
			if (job != null) analyze(job);
			else Sys.sleep(0.004);
		}
	}

	public function sync():Void {
		mutex.acquire();
		var r = workerRms;
		var p = workerPeak;
		for (b in 0...state.spectrum.length) binSums[b] = workerMag[b];
		mutex.release();
		publish(r, p);
	}
	#end

	// ——————————————————————————————
	// Web
	// ——————————————————————————————
	#if js
	public function browse():Void {
		var input = js.Browser.document.createInputElement();
		input.type = "file";
		input.accept = "audio/*";
		input.onchange = function(_) {
			if (input.files.length > 0) {
				var f = input.files[0];
				state.fileName = f.name;
				var reader = new js.html.FileReader();
				reader.onload = function(_) {
					webLoad(cast(reader.result, js.html.ArrayBuffer));
				};
				reader.readAsArrayBuffer(f);
			}
		};
		input.click();
	}

	public function webLoad(ab:js.html.ArrayBuffer):Void {
		if (webCtx == null) {
			webCtx = new js.html.audio.AudioContext();
			webGain = webCtx.createGain();
			webGain.connect(webCtx.destination);
		}
		pause();
		webCtx.decodeAudioData(ab, function(buf:js.html.audio.AudioBuffer) {
			webBuffer = buf;
			webData = buf.getChannelData(0);
			state.sampleRate = buf.sampleRate;
			trace('Web: 解码完成 ' + buf.duration + 's');
		}, function(e) trace('Web: 解码失败'));
	}

	public function play():Void {
		if (webBuffer == null || state.playing) return;
		webSource = webCtx.createBufferSource();
		webSource.buffer = webBuffer;
		webSource.loop = true;
		webSource.connect(webGain);
		webSource.start(0, webOffset);
		webStartCtxTime = webCtx.currentTime;
		state.playing = true;
		applyVolume();
	}

	public function pause():Void {
		if (!state.playing) return;
		webOffset = positionSec();
		if (webSource != null) { webSource.stop(); webSource = null; }
		state.playing = false;
	}

	function positionSec():Float {
		return state.playing ? webOffset + (webCtx.currentTime - webStartCtxTime) : webOffset;
	}

	public function applyVolume():Void {
		if (webGain != null) {
			webGain.gain.value = state.graphicsOnlyGain ? 1.0 : Math.min(1.5, state.gain);
		}
	}

	public function update():Void {
		if (webData != null) {
			var sr = state.sampleRate;
			var start = Std.int(positionSec() * sr);
			var total = webData.length;
			for (i in 0...chunk.length) {
				var idx = start + i;
				chunk[i] = (idx >= 0 && idx < total) ? webData[idx] : 0;
			}
		} else {
			demoSignal();
		}
		analyze(chunk);
	}

	public function sync():Void {}
	#end

	// ——————————————————————————————
	// 公共
	// ——————————————————————————————
	/** 演示信号：三正弦扫频 + 节拍包络，让首启/网页预览也有画面 */
	function demoSignal():Void {
		var t = haxe.Timer.stamp();
		var n = chunk.length;
		for (i in 0...n) {
			var tt = t + i / state.sampleRate;
			var beat = 0.5 + 0.5 * Math.sin(tt * 4.4);
			var v = 0.28 * beat * (Math.sin(tt * 2 * Math.PI * (80 + 30 * Math.sin(tt * 0.8)))
				+ 0.6 * Math.sin(tt * 2 * Math.PI * (440 + 180 * Math.sin(tt * 0.5)))
				+ 0.35 * Math.sin(tt * 2 * Math.PI * (1200 + 600 * Math.sin(tt * 0.33))));
			chunk[i] = v;
		}
	}

	/** 分析管线：压缩器 → 增益限幅 → FFT → 分桶 → 发布（含平滑） */
	function analyze(buf:Float32Array):Void {
		state.applyTo(compressor);
		compressor.process(buf, state.sampleRate);

		var sum = 0.0;
		for (i in 0...buf.length) {
			var x = buf[i] * state.gain;
			if (x > 1.5) x = 1.5; else if (x < -1.5) x = -1.5;
			buf[i] = x;
			sum += x * x;
		}
		var rms = Math.sqrt(sum / buf.length);

		fft.magnitude(buf, mag);

		var half = mag.length;
		var bins = state.spectrum.length;
		for (b in 0...bins) binSums[b] = 0;
		for (i in 0...half) {
			var b = Std.int(i * bins / half);
			binSums[b] += mag[i];
		}
		var peakVal = 0.0;
		var peakBin = 0;
		for (b in 0...bins) {
			var v = binSums[b] / (half / bins) * state.gain;
			if (v > 1.2) v = 1.2;
			binSums[b] = v;
			if (v > peakVal) { peakVal = v; peakBin = b; }
		}

		#if sys
		mutex.acquire();
		workerRms = rms;
		workerPeak = peakBin;
		for (b in 0...bins) workerMag[b] = binSums[b];
		mutex.release();
		#else
		publish(rms, peakBin);
		#end
	}

	function publish(rms:Float, peakBin:Int):Void {
		state.rms = rms;
		state.rmsSmooth += (rms - state.rmsSmooth) * 0.12;
		var bins = state.spectrum.length;
		for (b in 0...bins) state.spectrum[b] += (binSums[b] - state.spectrum[b]) * 0.35;
		state.maxFreq = peakBin * (state.sampleRate * 0.5) / bins;
	}
}
