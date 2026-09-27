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

	// —— GLSL 150 core 变体（桌面 core profile 回退）——
	static var FLAT_VERT_CORE =
		"#version 150\n" +
		"in vec2 aPos; in vec4 aColor; uniform vec2 uRes; uniform vec2 uScale; uniform vec2 uCenter; out vec4 vColor;" +
		"void main() { vec2 p = (aPos - uCenter) * uScale + uCenter; vec2 ndc = p / uRes * 2.0 - 1.0;" +
		"gl_Position = vec4(ndc.x, -ndc.y, 0.0, 1.0); vColor = aColor; }";
	static var FLAT_FRAG_CORE =
		"#version 150\n" +
		"in vec4 vColor; out vec4 fragColor;" +
		"void main() { fragColor = vColor; }";
	static var TEX_VERT_CORE =
		"#version 150\n" +
		"in vec2 aPos; in vec2 aUV; in vec4 aColor; uniform vec2 uRes; out vec2 vUV; out vec4 vColor;" +
		"void main() { vec2 ndc = aPos / uRes * 2.0 - 1.0; gl_Position = vec4(ndc.x, -ndc.y, 0.0, 1.0); vUV = aUV; vColor = aColor; }";
	static var TEX_FRAG_CORE =
		"#version 150\n" +
		"in vec2 vUV; in vec4 vColor; uniform sampler2D uTex; out vec4 fragColor;" +
		"void main() { fragColor = texture2D(uTex, vUV) * vColor; }";

	// diag9: 无顶点缓冲测试 program（gl_VertexID 生成全屏大三角，纯绿）——裁决 GL 管线本身
	static var TRI_VS_CORE =
		"#version 150\n" +
		"void main() { vec2 p = vec2((gl_VertexID == 1) ? 3.0 : -1.0, (gl_VertexID == 2) ? 3.0 : -1.0);" +
		"gl_Position = vec4(p, 0.0, 1.0); }";
	static var TRI_FS_CORE =
		"#version 150\n" +
		"out vec4 fragColor; void main() { fragColor = vec4(0.0, 1.0, 0.0, 1.0); }";

	var geo:Geo;
	var font:FontAtlas;

	/** 渲染回调传入的实例上下文（native=OpenGL / web=WebGL），函数一律走它 */
	public var gl:Dynamic;
	var flatProg:Dynamic;
	var texProg:Dynamic;
	var vboFlat:Dynamic;
	var vboTex:Dynamic;

	var fAPos:Int; var fAColor:Int;
	var fURes:Dynamic; var fUScale:Dynamic; var fUCenter:Dynamic;
	var tAPos:Int; var tAUV:Int; var tAColor:Int;
	var tURes:Dynamic; var tUTex:Dynamic;

	var bgTex:Dynamic;
	var bgImage:Image;
	var bgPixels:haxe.io.Bytes;
	var bgW:Int = 1;
	var bgH:Int = 1;
	var triProg:Dynamic;
	var ready:Bool = false;
	var frame:Int = 0;

	var state:VizState;
	var time:Float = 0;

	public function new(state:VizState) {
		this.state = state;
		geo = new Geo();
		font = new FontAtlas();       // 只读资产数据，不碰 GL
		bgImage = Image.fromFile("assets/back.png");
		if (bgImage == null) { SLog.log('back.png fromFile null!'); }
		else {
			SLog.log('back.png fromFile OK ' + bgImage.width + 'x' + bgImage.height);
			bgW = bgImage.width; bgH = bgImage.height;
			var u8:Dynamic = bgImage.data;
			var len:Int = bgW * bgH * 4;
			bgPixels = haxe.io.Bytes.alloc(len);
			for (i in 0...len) bgPixels.set(i, u8[i]);
			SLog.log('back.png 像素快照完成 ' + len);
		}
		// GL 资源延后到首帧渲染时创建（那时 GL 上下文才是当前的）
	}

	function initPrograms():Void {
		// 先试 GLSL ES（移动端/兼容 profile），失败换 GLSL 150 core（桌面 core profile）
		flatProg = GLUtil.tryBuildProgram(gl, FLAT_VERT, FLAT_FRAG, ["aPos", "aColor"]);
		if (flatProg == null) {
			SLog.log('flat: ES 失败 → 换 GLSL150');
			flatProg = GLUtil.tryBuildProgram(gl, FLAT_VERT_CORE, FLAT_FRAG_CORE, ["aPos", "aColor"]);
		}
		SLog.log('flat program ' + (flatProg != null ? 'OK' : 'FAIL'));
		fAColor = 1;
		fURes = gl.getUniformLocation(flatProg, "uRes");
		fUScale = gl.getUniformLocation(flatProg, "uScale");
		fUCenter = gl.getUniformLocation(flatProg, "uCenter");

		texProg = GLUtil.tryBuildProgram(gl, TEX_VERT, TEX_FRAG, ["aPos", "aUV", "aColor"]);
		if (texProg == null) {
			SLog.log('tex: ES 失败 → 换 GLSL150');
			texProg = GLUtil.tryBuildProgram(gl, TEX_VERT_CORE, TEX_FRAG_CORE, ["aPos", "aUV", "aColor"]);
		}
		SLog.log('tex program ' + (texProg != null ? 'OK' : 'FAIL'));
		tAUV = 1;
		tAColor = 2;
		tURes = gl.getUniformLocation(texProg, "uRes");
		tUTex = gl.getUniformLocation(texProg, "uTex");

		vboFlat = gl.createBuffer();
		vboTex = gl.createBuffer();

		// diag9: 无缓冲全屏三角 program（裁决管线）
		triProg = GLUtil.tryBuildProgram(gl, TRI_VS_CORE, TRI_FS_CORE, []);
		SLog.log('tri program ' + (triProg != null ? 'OK' : 'FAIL') + ' err=' + gl.getError());
		SLog.log('LOC flat: aPos=' + gl.getAttribLocation(flatProg, 'aPos') + ' aColor=' + gl.getAttribLocation(flatProg, 'aColor')
			+ ' uRes=' + fURes + ' uScale=' + fUScale + ' uCenter=' + fUCenter);
		SLog.log('LOC tex: aPos=' + gl.getAttribLocation(texProg, 'aPos') + ' aUV=' + gl.getAttribLocation(texProg, 'aUV')
			+ ' aColor=' + gl.getAttribLocation(texProg, 'aColor') + ' uRes=' + tURes + ' uTex=' + tUTex);
	}

	function initTextures():Void {
		if (bgPixels != null) {
			bgTex = gl.createTexture();
			gl.bindTexture(gl.TEXTURE_2D, bgTex);
			GLUtil.uploadTexture(gl, gl.TEXTURE_2D, bgW, bgH, bgPixels);
			SLog.log('bgTex err=' + gl.getError());
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
		} else {
			SLog.log('背景图缺失，纯色背景');
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

		// diag7: 巨型纯红测试块（裁决绘制链路：300x300 居中）
		geo.fQuad(w * 0.5 - 150, h * 0.5 - 150, w * 0.5 + 150, h * 0.5 - 150,
			w * 0.5 + 150, h * 0.5 + 150, w * 0.5 - 150, h * 0.5 + 150,
			1, 0, 0, 1);
	}

	// ——————————————————————————————
	// 帧渲染
	// ——————————————————————————————
	/** 帧开始：由 Main 先调用（UI 先画，场景后画，都在同一缓冲） */
	public function clearFrame():Void {
		geo.clear();
	}

	public function draw(w:Float, h:Float, dt:Float):Void {
		if (!ready) {
			SLog.log('draw#0: initPrograms 前');
			initPrograms();
			SLog.log('draw#0: initPrograms 后');
			initTextures();
			SLog.log('draw#0: initTextures 后');
			font.ensureTexture(gl);
			SLog.log('draw#0: ensureTexture 后');
			ready = true;
		}
		time += dt;
		if (frame <= 8) SLog.log('draw#' + frame + ': buildScene 前');
		buildScene(w, h);
		geo.syncBytes();
		if (frame <= 8) SLog.log('draw#' + frame + ': buildScene 后');
		if (frame <= 2) {
			gl.viewport(0, 0, 1, 1);
			SLog.log('draw#' + frame + ': viewport 探针 err=' + gl.getError());
		}

		var cx = w * 0.5, cy = h * 0.5;
		var jelly = 1.0 + state.rmsSmooth * 0.5 * Math.min(2.0, state.gain);
		var edgeCount = 12;

		// 背景 quad 推入 tex 流（文字已在前面推入）
		var bgStart = Std.int(geo.texCount / 8);
		geo.tQuad(0, 0, w, 0, w, h, 0, h, 0, 0, 1, 1, 1, 1, 1, 1);
		var bgCount = Std.int(geo.texCount / 8) - bgStart;
		var textStart = bgStart + bgCount;
		var textCount = Std.int(geo.texCount / 8) - textStart;
		frame++;

		gl.viewport(0, 0, Std.int(w), Std.int(h));
		gl.disable(GL.DEPTH_TEST);
		gl.enable(GL.BLEND);
		gl.blendFunc(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA);
		gl.clearColor(1, 0, 1, 1); // diag7: 品红清屏（裁决呈现链路）
		gl.clear(GL.COLOR_BUFFER_BIT);

		// —— 先上传 tex VBO（背景+文字共用），再画 ——
		if (frame <= 1) SLog.log('draw#' + frame + ': tex 上传前 texCount=' + geo.texCount);
		gl.useProgram(texProg);
		gl.uniform2f(tURes, w, h);
		gl.uniform1i(tUTex, 0);
		gl.activeTexture(GL.TEXTURE0);
		if (font.textureId != null) gl.bindTexture(GL.TEXTURE_2D, font.textureId);
		gl.bindBuffer(GL.ARRAY_BUFFER, vboTex);
		if (geo.texCount > 0) {
			GLUtil.uploadBuffer(gl, GL.ARRAY_BUFFER, geo.texBytes, geo.texCount * 4);
			if (frame <= 2) SLog.log('texUpload后 err=' + gl.getError() + ' bytes=' + gl.getBufferParameter(GL.ARRAY_BUFFER, gl.BUFFER_SIZE));
		}
		gl.enableVertexAttribArray(tAPos);
		gl.vertexAttribPointer(tAPos, 2, GL.FLOAT, false, 32, 0);
		gl.enableVertexAttribArray(tAUV);
		gl.vertexAttribPointer(tAUV, 2, GL.FLOAT, false, 32, 8);
		gl.enableVertexAttribArray(tAColor);
		gl.vertexAttribPointer(tAColor, 4, GL.FLOAT, false, 32, 16);

		// Pass1 背景（底层）
		if (frame <= 1) SLog.log('draw#' + frame + ': bg 绘制前');
		if (bgTex != null && bgCount > 0) {
			gl.bindTexture(GL.TEXTURE_2D, bgTex);
			gl.drawArrays(GL.TRIANGLES, bgStart, bgCount);
			if (font.textureId != null) gl.bindTexture(GL.TEXTURE_2D, font.textureId);
		}

		// —— flat VBO 上传 + 中心组（果冻）+ 边缘组 ——
		if (frame <= 1) SLog.log('draw#' + frame + ': flat 上传前 flatCount=' + geo.flatCount);
		gl.useProgram(flatProg);
		gl.uniform2f(fURes, w, h);
		gl.bindBuffer(GL.ARRAY_BUFFER, vboFlat);
		if (geo.flatCount > 0) {
			GLUtil.uploadBuffer(gl, GL.ARRAY_BUFFER, geo.flatBytes, geo.flatCount * 4);
			if (frame <= 2) SLog.log('flatUpload后 err=' + gl.getError() + ' bytes=' + gl.getBufferParameter(GL.ARRAY_BUFFER, gl.BUFFER_SIZE));
		}
		gl.enableVertexAttribArray(fAPos);
		gl.vertexAttribPointer(fAPos, 2, GL.FLOAT, false, 24, 0);
		gl.enableVertexAttribArray(fAColor);
		gl.vertexAttribPointer(fAColor, 4, GL.FLOAT, false, 24, 8);

		var flatVerts = Std.int(geo.flatCount / 6); // float 数 → 顶点数（核心修复）
		gl.uniform2f(fUScale, jelly, jelly);
		gl.uniform2f(fUCenter, cx, cy);
		if (flatVerts > edgeCount) gl.drawArrays(GL.TRIANGLES, edgeCount, flatVerts - edgeCount);
		if (frame <= 2) SLog.log('flat后 err=' + gl.getError());
		gl.uniform2f(fUScale, 1.0, 1.0);
		gl.uniform2f(fUCenter, 0.0, 0.0);
		if (edgeCount <= flatVerts) gl.drawArrays(GL.TRIANGLES, 0, edgeCount);
		if (frame <= 2) SLog.log('edge后 err=' + gl.getError());

		// Pass2 文字（顶层）
		if (frame <= 1) SLog.log('draw#' + frame + ': 帧完成');
		if (textCount > 0 && font.textureId != null) {
			gl.useProgram(texProg);
			gl.uniform2f(tURes, w, h);
			gl.uniform1i(tUTex, 0);
			gl.activeTexture(GL.TEXTURE0);
			gl.bindTexture(GL.TEXTURE_2D, font.textureId);
			gl.bindBuffer(GL.ARRAY_BUFFER, vboTex);
			gl.enableVertexAttribArray(tAPos);
			gl.vertexAttribPointer(tAPos, 2, GL.FLOAT, false, 32, 0);
			gl.enableVertexAttribArray(tAUV);
			gl.vertexAttribPointer(tAUV, 2, GL.FLOAT, false, 32, 8);
			gl.enableVertexAttribArray(tAColor);
			gl.vertexAttribPointer(tAColor, 4, GL.FLOAT, false, 32, 16);
			gl.drawArrays(GL.TRIANGLES, textStart, textCount);
			if (frame <= 2) SLog.log('text后 err=' + gl.getError());
		}

		// diag9: 第 5 帧起每帧画无缓冲绿三角（裁决管线本身）
		if (frame >= 5 && triProg != null) {
			gl.useProgram(triProg);
			gl.disableVertexAttribArray(0);
			gl.disableVertexAttribArray(1);
			gl.disableVertexAttribArray(2);
			gl.drawArrays(GL.TRIANGLES, 0, 3);
			if (frame == 5) SLog.log('TRI drawn err=' + gl.getError());
		}
		// readPixels 在 lime native 段错误（DataPointer 第三个受害者），改用外部截屏裁决
	}

	public function getGeo():Geo return geo;
	public function getFont():FontAtlas return font;
}
