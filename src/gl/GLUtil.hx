package gl;

import lime.graphics.opengl.GL;
import lime.graphics.opengl.GLProgram;

#if cpp
import cpp.CFFI;
#end

/**
 * GL 工具。函数一律走"实例上下文"（onRender 传入的 gl），
 * 常量才允许用静态 GL（常量不需要上下文）。
 *
 * diag11d 关键修复：lime 7.9 的 DataPointer.fromBytes（cpp 目标）走 hxcpp
 * Pointer.arrayElem(bytes.b, 0) —— 对 Array<UInt8> 的 operator[] 取址，
 * 拿到的是栈上临时值地址（垃圾指针）。glBufferData/vertexAttribPointer/
 * texImage2D 传 Haxe 层 Bytes 全部变成传垃圾 → 场景绘制全哑、纹理全坏。
 * 这里改用 CFFI.load 加载 lime.ndll 的 lime_bytes_get_data_pointer
 * （C++ 侧直接返回 Bytes 底层连续 buffer 指针，lime 官方 neko/cppia
 * 分支的同款加载方式）。DataPointer 底层类型就是 Float（cpp 目标），
 * Float 直接可当 DataPointer 传。
 */
class GLUtil {

	#if cpp
	private static var _cffiLoaded:Bool = false;
	private static var _getPtr:Dynamic = null;

	/** haxe.io.Bytes → 底层连续内存指针（Float 形式；DataPointer 底层类型即 Float） */
	public static inline function bytesPointer(bytes:haxe.io.Bytes):Float {
		if (bytes == null) return 0;
		if (!_cffiLoaded) {
			_cffiLoaded = true;
			try {
				_getPtr = CFFI.load("lime", "lime_bytes_get_data_pointer", 1);
				SLog.log('CFFI.load lime_bytes_get_data_pointer OK');
			} catch (e:Dynamic) {
				SLog.log('CFFI.load 失败: ' + e);
				_getPtr = null;
			}
		}
		if (_getPtr == null) return 0;
		return untyped _getPtr(bytes);
	}
	#else
	public static inline function bytesPointer(bytes:haxe.io.Bytes):Float {
		return 0;
	}
	#end

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

	/** 跨目标 bufferData：cpp 用 lime CFFI 直取指针（绕过 fromBytes 的 arrayElem bug） */
	public static function uploadBuffer(gl:Dynamic, target:Int, bytes:haxe.io.Bytes, byteSize:Int):Void {
		#if js
		untyped gl.bufferData(target, bytes, GL.DYNAMIC_DRAW);
		#elseif cpp
		var f:Float = bytesPointer(bytes);
		untyped gl.bufferData(target, byteSize, f, GL.DYNAMIC_DRAW);
		#else
		gl.bufferData(target, byteSize, bytes, GL.DYNAMIC_DRAW);
		#end
	}

	/** 跨目标 texImage2D：native 传像素 Bytes */
	public static function uploadTexture(gl:Dynamic, target:Int, w:Int, h:Int, pixels:haxe.io.Bytes):Void {
		#if js
		untyped gl.texImage2D(target, 0, GL.RGBA, w, h, 0, GL.RGBA, GL.UNSIGNED_BYTE, pixels.getData());
		#elseif cpp
		var f:Float = bytesPointer(pixels);
		untyped gl.texImage2D(target, 0, GL.RGBA, w, h, 0, GL.RGBA, GL.UNSIGNED_BYTE, f);
		#else
		gl.texImage2D(target, 0, GL.RGBA, w, h, 0, GL.RGBA, GL.UNSIGNED_BYTE, pixels);
		#end
	}
}
