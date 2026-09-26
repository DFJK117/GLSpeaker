package gl;

import lime.graphics.opengl.GL;
import lime.graphics.opengl.GLBuffer;
import lime.graphics.opengl.GLProgram;
import lime.graphics.opengl.GLTexture;
import lime.graphics.opengl.GLUniformLocation;
import lime.graphics.Image;
import lime.utils.Assets;
import lime.utils.UInt8Array;

/**
 * OpenGL 渲染器（还原原版 MainView.onDraw 分层，全部 GPU）：
 *   Pass1 背景纹理全屏 quad
 *   Pass2 中心组（果冻缩放）：圆形频谱 + 喇叭图标 + 旋转装饰弧
 *   Pass3 边缘 RMS 柱（不缩放）
 *   Pass4 文字（字体图集）
 * 果冻缩放在顶点着色器完成。
 */
class GLRenderer {

	static var FLAT_VERT = "
		attribute vec2 aPos;
		attribute vec4 aColor;
		uniform vec2 uRes;
		uniform vec2 uScale;
		uniform vec2 uCenter;
		varying vec4 vColor;
		void main() {
			vec2 p = (aPos - uCenter) * uScale + uCenter;
			vec2 ndc = p / uRes * 2.0 - 1.0;
			gl_Position = vec4(ndc.x, -ndc.y, 0.0, 1.0);
			vColor = aColor;
		}";

	static var FLAT_FRAG = "
		#ifdef GL_ES
		precision mediump float;
		#endif
		varying vec4 vColor;
		void main() { gl_FragColor = vColor; }";

	static var TEX_VERT = "
		attribute vec2 aPos;
		attribute vec2 aUV;
		attribute vec4 aColor;
		uniform vec2 uRes;
		varying vec2 vUV;
		varying vec4 vColor;
		void main() {
			vec2 ndc = aPos / uRes * 2.0 - 1.0;
			gl_Position = vec4(ndc.x, -ndc.y, 0.0, 1.0);
			vUV = aUV;
			vColor = aColor;
		}";

	static var TEX_FRAG = "
		#ifdef GL_ES
		precision mediump float;
		#endif
		uniform sampler2D uTex;
		varying vec2 vUV;
		varying vec4 vColor;
		void main() { gl_FragColor = texture2D(uTex, vUV) * vColor; }";

	var geo:Geo;
	var font:FontAtlas;

	var flatProg:GLProgram;
	var texProg:GLProgram;
	var vboFlat:GLBuffer;
	var vboTex:GLBuffer;

	var fAPos:Int; var fAColor:Int;
	var fURes:GLUniformLocation; var fUScale:GLUniformLocation; var fUCenter:GLUniformLocation;
	var tAPos:Int; var tAUV:Int; var tAColor:Int;
	var tURes:GLUniformLocation; var tUTex:GLUniformLocation;

	var bgTex:GLTexture;
	var bgImage:Image;
	var ready:Bool = false;

	var state:VizState;
	var time:Float = 0;

	public function new(state:VizState) {
		this.state = state;
		geo = new Geo();
		font = new FontAtlas();       // 只读资产数据，不碰 GL
		bgImage = Assets.getImage("assets/back.png");
		// GL 资源延后到首帧渲染时创建（那时 GL 上下文才是当前的）
	}

	function initPrograms():Void {
		flatProg = GLUtil.buildProgram(FLAT_VERT, FLAT_FRAG, ["aPos", "aColor"]);
		fAColor = 1;
		fURes = GL.getUniformLocation(flatProg, "uRes");
		fUScale = GL.getUniformLocation(flatProg, "uScale");
		fUCenter = GL.getUniformLocation(flatProg, "uCenter");

		texProg = GLUtil.buildProgram(TEX_VERT, TEX_FRAG, ["aPos", "aUV", "aColor"]);
		tAUV = 1;
		tAColor = 2;
		tURes = GL.getUniformLocation(texProg, "uRes");
		tUTex = GL.getUniformLocation(texProg, "uTex");

		vboFlat = GL.createBuffer();
		vboTex = GL.createBuffer();
	}

	function initTextures():Void {
		var img:Image = bgImage;
		if (img != null) {
			bgTex = GL.createTexture();
			GL.bindTexture(GL.TEXTURE_2D, bgTex);
			GLUtil.uploadTexture(GL.TEXTURE_2D, img);
			GL.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.LINEAR);
			GL.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.LINEAR);
			GL.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, GL.CLAMP_TO_EDGE);
			GL.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, GL.CLAMP_TO_EDGE);
		} else {
			trace('背景图 assets/back.png 缺失');
		}
	}

	// ——————————————————————————————
	// 场景几何
	// ——————————————————————————————
	function buildScene(w:Float, h:Float):Void {
		// geo 已由 clearFrame 清空

		// —— 中心组（果冻缩放）——
		var cx = w * 0.5, cy = h * 0.5;
		var R0 = Math.min(w, h) * 0.30;

		var bins = state.spectrum.length;
		var stepA = Math.PI * 2 / bins;
		var bw = stepA * R0 * 0.45;
		for (i in 0...bins) {
			var m = state.spectrum[i];
			var len = Math.max(2, m * R0 * 0.9);
			var ang = i * stepA - Math.PI * 0.5;
			var ca = Math.cos(ang), sa = Math.sin(ang);
			var px = -sa, py = ca;
			var ix = cx + ca * R0, iy = cy + sa * R0;
			var ox = cx + ca * (R0 + len), oy = cy + sa * (R0 + len);
			var hw = bw * 0.5;
			var t = i / bins;
			geo.fQuad(ix + px * hw, iy + py * hw, ox + px * hw, oy + py * hw,
				ox - px * hw, oy - py * hw, ix - px * hw, iy - py * hw,
				0.1 + t * 0.9, 0.9 - t * 0.5, 1.0, 0.9);
		}

		// 喇叭图标
		var size = R0 * 0.9;
		var rC:Float = 1.0, gC:Float = 0.62, bC:Float = 0.13;
		var bw2 = size * 0.36, hh = size * 0.30, cone = size * 0.42;
		var sx = cx - size * 0.5;
		geo.fRect(sx, cy - hh * 0.5, bw2, hh, rC, gC, bC, 0.92);
		geo.fQuad(sx + bw2, cy - hh * 0.5, sx + bw2 + cone, cy - size * 0.5,
			sx + bw2 + cone, cy + size * 0.5, sx + bw2, cy + hh * 0.5, rC, gC, bC, 0.92);
		var pulse = 0.25 + 0.55 * Math.min(1, state.rmsSmooth * 2.2);
		geo.fArc(cx, cy, size * 0.72, 48, 0, Math.PI * 2, size * 0.035, 1, 1, 1, pulse);

		// 旋转装饰弧（对应原版 dvl）
		var a1 = time * 0.9, a2 = -time * 0.9 + Math.PI;
		geo.fArc(cx, cy, R0 + 34, 24, a1, a1 + 1.1, 5, 1, 1, 1, 0.22);
		geo.fArc(cx, cy, R0 + 34, 24, a2, a2 + 1.1, 5, 1, 1, 1, 0.22);

		// —— 边缘 RMS 柱 ——
		var rw = 50.0;
		var lh = Math.min(1, state.rmsSmooth * 1.6) * h;
		geo.fRect(0, h - lh, rw, lh, 0.1, 1.0, 0.45, 0.85);
		geo.fRect(w - rw, 0, rw, lh, 0.1, 1.0, 0.45, 0.85);
	}

	// ——————————————————————————————
	// 帧渲染
	// ——————————————————————————————
	/** 帧开始：由 Main 先调用（UI 先画，场景后画，都在同一缓冲） */
	public function clearFrame():Void {
		geo.clear();
		_bgVertStart = 0;
		_bgVertCount = 0;
	}

	public function draw(w:Float, h:Float, dt:Float):Void {
		if (!ready) {
			initPrograms();
			initTextures();
			font.ensureTexture();
			ready = true;
		}
		time += dt;
		buildScene(w, h);

		GL.viewport(0, 0, Std.int(w), Std.int(h));
		GL.disable(GL.DEPTH_TEST);
		GL.enable(GL.BLEND);
		GL.blendFunc(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA);
		GL.clearColor(0, 0, 0, 1);
		GL.clear(GL.COLOR_BUFFER_BIT);

		// Pass1 背景纹理
		if (bgTex != null) {
			GL.useProgram(texProg);
			GL.uniform2f(tURes, w, h);
			GL.uniform1i(tUTex, 0);
			GL.activeTexture(GL.TEXTURE0);
			GL.bindTexture(GL.TEXTURE_2D, bgTex);
			GL.bindBuffer(GL.ARRAY_BUFFER, vboTex);
			GL.enableVertexAttribArray(tAPos);
			GL.vertexAttribPointer(tAPos, 2, GL.FLOAT, false, 32, 0);
			GL.enableVertexAttribArray(tAUV);
			GL.vertexAttribPointer(tAUV, 2, GL.FLOAT, false, 32, 8);
			GL.enableVertexAttribArray(tAColor);
			GL.vertexAttribPointer(tAColor, 4, GL.FLOAT, false, 32, 16);
			// 临时把全屏 quad 塞进 tex 流（先复用 geo.tex 头部？不行——直接推背景 quad 到 tex 流）
			drawBgQuad(w, h);
		}

		// Pass2 中心组（果冻） + Pass3 边缘组
		var cx = w * 0.5, cy = h * 0.5;
		var jelly = 1.0 + state.rmsSmooth * 0.5 * Math.min(2.0, state.gain);
		GL.useProgram(flatProg);
		GL.uniform2f(fURes, w, h);
		GL.bindBuffer(GL.ARRAY_BUFFER, vboFlat);
		GLUtil.uploadBuffer(GL.ARRAY_BUFFER, geo.flat, geo.flatCount * 4);
		GL.enableVertexAttribArray(fAPos);
		GL.vertexAttribPointer(fAPos, 2, GL.FLOAT, false, 24, 0);
		GL.enableVertexAttribArray(fAColor);
		GL.vertexAttribPointer(fAColor, 4, GL.FLOAT, false, 24, 8);

		// 顶点布局: [0..12) 边缘柱, [12..flatCount) 中心组
		GL.uniform2f(fUScale, jelly, jelly);
		GL.uniform2f(fUCenter, cx, cy);
		if (geo.flatCount > 12) GL.drawArrays(GL.TRIANGLES, 12, geo.flatCount - 12);
		GL.uniform2f(fUScale, 1.0, 1.0);
		GL.uniform2f(fUCenter, 0.0, 0.0);
		GL.drawArrays(GL.TRIANGLES, 0, 12);

		// Pass4 文字
		if (geo.texCount > 0 && font.textureId != null) {
			GL.useProgram(texProg);
			GL.uniform2f(tURes, w, h);
			GL.uniform1i(tUTex, 0);
			GL.activeTexture(GL.TEXTURE0);
			GL.bindTexture(GL.TEXTURE_2D, font.textureId);
			GL.bindBuffer(GL.ARRAY_BUFFER, vboTex);
			GLUtil.uploadBuffer(GL.ARRAY_BUFFER, geo.tex, geo.texCount * 4);
			GL.enableVertexAttribArray(tAPos);
			GL.vertexAttribPointer(tAPos, 2, GL.FLOAT, false, 32, 0);
			GL.enableVertexAttribArray(tAUV);
			GL.vertexAttribPointer(tAUV, 2, GL.FLOAT, false, 32, 8);
			GL.enableVertexAttribArray(tAColor);
			GL.vertexAttribPointer(tAColor, 4, GL.FLOAT, false, 32, 16);
			GL.drawArrays(GL.TRIANGLES, _bgVertStart + _bgVertCount, Std.int(geo.texCount / 8) - (_bgVertStart + _bgVertCount));
		}
	}

	/** 背景全屏 quad 追加到 tex 流尾部，并返回其起始顶点偏移（供 drawArrays 用） */
	var _bgVertStart:Int = 0;
	var _bgVertCount:Int = 0;

	function drawBgQuad(w:Float, h:Float):Void {
		_bgVertStart = Std.int(geo.texCount / 8);
		geo.tQuad(0, 0, w, 0, w, h, 0, h, 0, 0, 1, 1, 1, 1, 1, 1);
		_bgVertCount = Std.int(geo.texCount / 8) - _bgVertStart;
		GL.drawArrays(GL.TRIANGLES, _bgVertStart, _bgVertCount);
	}

	function bgQuadVerts():Int {
		return _bgVertStart + _bgVertCount;
	}

	public function getGeo():Geo return geo;
	public function getFont():FontAtlas return font;
}
