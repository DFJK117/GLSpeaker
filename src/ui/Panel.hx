package ui;

import audio.AudioEngine;
import gl.FontAtlas;
import gl.Geo;

/**
 * 压缩器面板（纯 GL 绘制，右侧悬浮）：
 *   增益 / 阈值 / 比率 滑块 + 「仅增益图形不增益音频」开关 + 打开文件/播放按钮 + 文件名
 * 坐标为面板本地坐标；Main 负责 x/y 与鼠标路由。
 */
class Panel {

	public static inline var W:Float = 250;
	public static inline var H:Float = 348;
	static inline var PAD:Float = 16;

	public var x:Float = 0;
	public var y:Float = 0;

	var state:VizState;
	var engine:AudioEngine;

	var gainSlider:Slider;
	var thrSlider:Slider;
	var ratioSlider:Slider;
	var gainToggle:Toggle;
	var openBtn:Button;
	var playBtn:Button;

	public function new(state:VizState, engine:AudioEngine) {
		this.state = state;
		this.engine = engine;
		var iw = W - PAD * 2;
		var y0 = 44.0;

		gainSlider = new Slider("增益 Gain", 0.5, 4.0, state.gain, PAD, y0, iw, function(v) return Std.string(Math.round(v * 100) / 100) + "x");
		gainSlider.onChange = function(v) { state.gain = v; engine.applyVolume(); };
		y0 += 56;

		thrSlider = new Slider("阈值 Threshold", -60, 0, state.thresholdDb, PAD, y0, iw, function(v) return Std.int(v) + " dB");
		thrSlider.onChange = function(v) state.thresholdDb = v;
		y0 += 56;

		ratioSlider = new Slider("比率 Ratio", 1, 20, state.ratio, PAD, y0, iw, function(v) return Std.string(Math.round(v * 10) / 10) + ":1");
		ratioSlider.onChange = function(v) state.ratio = v;
		y0 += 56;

		gainToggle = new Toggle("仅增益图形不增益音频", PAD, y0, iw, state.graphicsOnlyGain);
		gainToggle.onChange = function(on) { state.graphicsOnlyGain = on; engine.applyVolume(); };
		y0 += 42;

		var bw = (iw - 10) / 2;
		openBtn = new Button("打开文件", PAD, y0, bw);
		openBtn.onClick = function() engine.browse();
		playBtn = new Button("播放", PAD + bw + 10, y0, bw);
		playBtn.onClick = function() {
			if (state.playing) engine.pause(); else engine.play();
		};
	}

	public function draw(geo:Geo, font:FontAtlas, nowPlaying:Bool, fileName:String):Void {
		// 面板底
		geo.fRoundRect(x, y, W, H, 14, 0.07, 0.075, 0.10, 0.92);
		// 标题
		font.drawText(geo, "压缩器 Compressor", x + PAD, y + 14, 0.35, 1, 1, 1, 0.95);

		gainSlider.draw(geo, font, x, y);
		thrSlider.draw(geo, font, x, y);
		ratioSlider.draw(geo, font, x, y);
		gainToggle.draw(geo, font, x, y);
		openBtn.draw(geo, font, x, y);
		playBtn.title = nowPlaying ? "暂停" : "播放";
		playBtn.draw(geo, font, x, y);

		font.drawText(geo, "文件: " + fileName, x + PAD, y + H - 26, 0.28, 0.6, 0.61, 0.66, 0.9);
	}

	// ———————— 鼠标路由（全局坐标 → 本地） ————————
	public function mouseDown(gx:Float, gy:Float):Void {
		var lx = gx - x, ly = gy - y;
		gainSlider.mouseDown(lx, ly);
		thrSlider.mouseDown(lx, ly);
		ratioSlider.mouseDown(lx, ly);
		gainToggle.mouseDown(lx, ly);
		openBtn.mouseDown(lx, ly);
		playBtn.mouseDown(lx, ly);
	}

	public function mouseMove(gx:Float, gy:Float):Void {
		var lx = gx - x, ly = gy - y;
		gainSlider.mouseMove(lx, ly);
		thrSlider.mouseMove(lx, ly);
		ratioSlider.mouseMove(lx, ly);
	}

	public function mouseUp(gx:Float, gy:Float):Void {
		var lx = gx - x, ly = gy - y;
		gainSlider.mouseUp(lx, ly);
		thrSlider.mouseUp(lx, ly);
		ratioSlider.mouseUp(lx, ly);
		openBtn.mouseUp(lx, ly);
		playBtn.mouseUp(lx, ly);
	}
}

/** 值格式 */
typedef Fmt = Float->String;

class Slider {

	public var onChange:Float->Void;
	public var title:String;
	public var min:Float;
	public var max:Float;
	public var value:Float;
	public var fmt:Fmt;

	var ox:Float; var oy:Float; var w:Float;
	var dragging:Bool = false;

	public function new(title:String, min:Float, max:Float, value:Float, ox:Float, oy:Float, w:Float, fmt:Fmt) {
		this.title = title; this.min = min; this.max = max; this.value = value;
		this.ox = ox; this.oy = oy; this.w = w; this.fmt = fmt;
	}

	function clampSet(v:Float) {
		value = v < min ? min : (v > max ? max : v);
		if (onChange != null) onChange(value);
	}

	public function draw(geo:Geo, font:FontAtlas, px:Float, py:Float):Void {
		var bx = px + ox, by = py + oy;
		font.drawText(geo, title, bx, by, 0.30, 0.78, 0.79, 0.83, 0.95);
		var valStr = fmt(value);
		var vw = font.measure(valStr, 0.30);
		font.drawText(geo, valStr, bx + w - vw, by, 0.30, 0, 0.9, 0.63, 0.95);

		var ty = by + 24;
		geo.fRoundRect(bx, ty, w, 6, 3, 0.16, 0.17, 0.22, 1.0);
		var t = (value - min) / (max - min);
		geo.fRoundRect(bx, ty, Math.max(8, w * t), 6, 3, 0, 0.9, 0.63, 1.0);
		geo.fFan(bx + w * t, ty + 3, 8, 16, 1, 1, 1, 1);
		geo.fFan(bx + w * t, ty + 3, 4, 12, 0, 0.9, 0.63, 1.0);
	}

	public function mouseDown(gx:Float, gy:Float):Void {
		if (inTrack(gx, gy)) { dragging = true; apply(gx); }
	}

	public function mouseMove(gx:Float, gy:Float):Void {
		if (dragging) apply(gx);
	}

	public function mouseUp(gx:Float, gy:Float):Void dragging = false;

	inline function inTrack(gx:Float, gy:Float):Bool {
		return gx >= ox - 8 && gx <= ox + w + 8 && gy >= oy + 14 && gy <= oy + 40;
	}

	function apply(gx:Float):Void {
		var t = (gx - ox) / w;
		if (t < 0) t = 0; else if (t > 1) t = 1;
		clampSet(min + (max - min) * t);
	}
}

class Toggle {

	public var onChange:Bool->Void;
	public var value:Bool;
	var title:String;
	var ox:Float; var oy:Float; var w:Float;

	public function new(title:String, ox:Float, oy:Float, w:Float, value:Bool) {
		this.title = title; this.ox = ox; this.oy = oy; this.w = w; this.value = value;
	}

	public function draw(geo:Geo, font:FontAtlas, px:Float, py:Float):Void {
		var bx = px + ox, by = py + oy;
		font.drawText(geo, title, bx, by, 0.30, 0.78, 0.79, 0.83, 0.95);
		var pillX = bx + w - 40;
		geo.fRoundRect(pillX, by + 1, 40, 20, 10,
			value ? 0 : 0.16, value ? 0.9 : 0.17, value ? 0.63 : 0.22, 1.0);
		geo.fFan(pillX + (value ? 30 : 10), by + 11, 7, 14, 1, 1, 1, 1);
	}

	public function mouseDown(gx:Float, gy:Float):Void {
		if (gx >= ox + w - 44 && gx <= ox + w && gy >= oy - 4 && gy <= oy + 26) {
			value = !value;
			if (onChange != null) onChange(value);
		}
	}

	public function mouseMove(gx:Float, gy:Float):Void {}
	public function mouseUp(gx:Float, gy:Float):Void {}
}

class Button {

	public var title:String;
	public var onClick:Void->Void;
	var ox:Float; var oy:Float; var w:Float; var h:Float;
	var pressed:Bool = false;

	public function new(title:String, ox:Float, oy:Float, w:Float, h:Float = 32) {
		this.title = title; this.ox = ox; this.oy = oy; this.w = w; this.h = h;
	}

	public function draw(geo:Geo, font:FontAtlas, px:Float, py:Float):Void {
		var bx = px + ox, by = py + oy;
		if (pressed) {
			geo.fRoundRect(bx, by, w, h, 10, 0, 0.9, 0.63, 1.0);
			var tw = font.measure(title, 0.33);
			font.drawText(geo, title, bx + (w - tw) / 2, by + 8, 0.33, 0.06, 0.07, 0.10, 1.0);
		} else {
			geo.fRoundRect(bx, by, w, h, 10, 0.14, 0.145, 0.185, 1.0);
			var tw = font.measure(title, 0.33);
			font.drawText(geo, title, bx + (w - tw) / 2, by + 8, 0.33, 0.91, 0.92, 0.94, 1.0);
		}
	}

	public function mouseDown(gx:Float, gy:Float):Void {
		pressed = hit(gx, gy);
	}

	public function mouseMove(gx:Float, gy:Float):Void {}

	public function mouseUp(gx:Float, gy:Float):Void {
		if (pressed && hit(gx, gy) && onClick != null) onClick();
		pressed = false;
	}

	inline function hit(gx:Float, gy:Float):Bool {
		return gx >= ox && gx <= ox + w && gy >= oy && gy <= oy + h;
	}
}
