package gl;

import lime.graphics.opengl.GL;
import lime.graphics.opengl.GLProgram;

/**
 * GL 工具。函数一律走"实例上下文"（onRender 传入的 gl），
 * 常量才允许用静态 GL（常量不需要上下文）。
 */
class GLUtil {

	/** 构建着色器程序；失败时返回 null 并写日志（供调用方走回退/诊断） */
	public static function tryBuildProgram(gl:Dynamic, vsSrc:String, fsSrc:String, attribs:Array<String>):Dynamic {
		var program:Dynamic = gl.createProgram();

		var vs = gl.createShader(GL.VERTEX_SHADER);
		gl.shaderSource(vs, vsSrc);
		gl.compileShader(vs);
		if (gl.getShaderParameter(vs, GL.COMPILE_STATUS) != 1) {
			SLog.log('VS 编译失败: ' + gl.getShaderInfoLog(vs));
			return null;
		}
		var fs = gl.createShader(GL.FRAGMENT_SHADER);
		gl.shaderSource(fs, fsSrc);
		gl.compileShader(fs);
		if (gl.getShaderParameter(fs, GL.COMPILE_STATUS) != 1) {
			SLog.log('FS 编译失败: ' + gl.getShaderInfoLog(fs));
			return null;
		}

		gl.attachShader(program, vs);
		gl.attachShader(program, fs);
		for (i in 0...attribs.length) {
			gl.bindAttribLocation(program, i, attribs[i]);
		}
		gl.linkProgram(program);
		if (gl.getProgramParameter(program, GL.LINK_STATUS) != 1) {
			SLog.log('Program 链接失败: ' + gl.getProgramInfoLog(program));
			return null;
		}
		return program;
	}

	/** 跨目标 bufferData：一律走 haxe.io.Bytes（lime 类型数组的 DataPointer 编组在原生端不可靠） */
	public static function uploadBuffer(gl:Dynamic, target:Int, bytes:haxe.io.Bytes, byteSize:Int):Void {
		#if js
		untyped gl.bufferData(target, bytes, GL.DYNAMIC_DRAW);
		#else
		gl.bufferData(target, byteSize, bytes, GL.DYNAMIC_DRAW);
		#end
	}

	/** 跨目标 texImage2D：native 传像素 Bytes */
	public static function uploadTexture(gl:Dynamic, target:Int, w:Int, h:Int, pixels:haxe.io.Bytes):Void {
		#if js
		untyped gl.texImage2D(target, 0, GL.RGBA, w, h, 0, GL.RGBA, GL.UNSIGNED_BYTE, pixels.getData());
		#else
		gl.texImage2D(target, 0, GL.RGBA, w, h, 0, GL.RGBA, GL.UNSIGNED_BYTE, pixels);
		#end
	}
}
