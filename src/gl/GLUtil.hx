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

	/** 跨目标 bufferData：WebGL 3 参，桌面 GL 4 参（lime_webgl 宏不可靠，用 js 判定） */
	public static function uploadBuffer(gl:Dynamic, target:Int, data:Dynamic, byteSize:Int):Void {
		#if js
		gl.bufferData(target, data, GL.DYNAMIC_DRAW);
		#else
		gl.bufferData(target, byteSize, data, GL.DYNAMIC_DRAW);
		#end
	}

	/** 跨目标 texImage2D：native 走 Bytes 通道（UInt8Array 的 DataPointer 编组在原生端段错误） */
	public static function uploadTexture(gl:Dynamic, target:Int, img:Dynamic):Void {
		#if js
		gl.texImage2D(target, 0, GL.RGBA, img.width, img.height, 0, GL.RGBA, GL.UNSIGNED_BYTE, img.data);
		#else
		var u8:Dynamic = img.data;
		if (u8 == null) { SLog.log('uploadTexture: img.data 为 null!'); return; }
		var len:Int = u8.length;
		SLog.log('uploadTexture: len=' + len + ' ' + img.width + 'x' + img.height);
		var bytes = haxe.io.Bytes.alloc(len);
		for (i in 0...len) bytes.set(i, u8[i]);
		gl.texImage2D(target, 0, GL.RGBA, img.width, img.height, 0, GL.RGBA, GL.UNSIGNED_BYTE, bytes);
		SLog.log('uploadTexture: 完成 err=' + gl.getError());
		#end
	}
}
