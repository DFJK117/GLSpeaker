package gl;

import lime.graphics.Image;
import lime.graphics.opengl.GL;
import lime.graphics.opengl.GLProgram;
import lime.utils.Float32Array;

class GLUtil {

	public static function buildProgram(vsSrc:String, fsSrc:String, attribs:Array<String>):GLProgram {
		var program = GL.createProgram();

		var vs = GL.createShader(GL.VERTEX_SHADER);
		GL.shaderSource(vs, vsSrc);
		GL.compileShader(vs);
		if (GL.getShaderParameter(vs, GL.COMPILE_STATUS) != 1) {
			trace('VS 编译失败: ' + GL.getShaderInfoLog(vs));
		}
		var fs = GL.createShader(GL.FRAGMENT_SHADER);
		GL.shaderSource(fs, fsSrc);
		GL.compileShader(fs);
		if (GL.getShaderParameter(fs, GL.COMPILE_STATUS) != 1) {
			trace('FS 编译失败: ' + GL.getShaderInfoLog(fs));
		}

		GL.attachShader(program, vs);
		GL.attachShader(program, fs);
		for (i in 0...attribs.length) {
			GL.bindAttribLocation(program, i, attribs[i]);
		}
		GL.linkProgram(program);
		if (GL.getProgramParameter(program, GL.LINK_STATUS) != 1) {
			trace('Program 链接失败: ' + GL.getProgramInfoLog(program));
		}
		return program;
	}

	/** 跨目标 bufferData：桌面用 DataPointer 版，webgl 用 WEBGL 版 */
	public static function uploadBuffer(target:Int, data:Float32Array, byteSize:Int):Void {
		#if lime_webgl
		GL.bufferDataWEBGL(target, data, GL.DYNAMIC_DRAW);
		#else
		GL.bufferData(target, byteSize, data, GL.DYNAMIC_DRAW);
		#end
	}

	/** 跨目标 texImage2D（上传 lime Image） */
	public static function uploadTexture(target:Int, img:Image):Void {
		#if lime_webgl
		GL.texImage2DWEBGL(target, 0, GL.RGBA, img.width, img.height, 0, GL.RGBA, GL.UNSIGNED_BYTE, img);
		#else
		GL.texImage2D(target, 0, GL.RGBA, img.width, img.height, 0, GL.RGBA, GL.UNSIGNED_BYTE, img.data);
		#end
	}
}
