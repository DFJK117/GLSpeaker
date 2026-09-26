package gl;

import haxe.Json;
import lime.graphics.Image;

/**
 * 字体图集：tools/gen_font_atlas.py 预生成的 PNG + JSON。
 * 构造时从磁盘解码并立刻快照像素到自有 Bytes（lime Image 数据在原生端会被动失效）。
 * 纹理在首帧渲染时创建（GL 上下文激活后），drawText 把字符作为 UV quad 推入 Geo.tex。
 */
class FontAtlas {

	public var textureId:Dynamic = null;
	public var imgW:Float = 1;
	public var imgH:Float = 1;

	var meta:Dynamic;
	var size:Float;
	var pixels:haxe.io.Bytes;

	public function new() {
		var img = Image.fromFile("assets/font_atlas.png");
		if (img == null) {
			SLog.log('font_atlas fromFile null!');
			return;
		}
		imgW = img.width;
		imgH = img.height;
		SLog.log('font_atlas fromFile OK ' + imgW + 'x' + imgH);
		// 像素快照（RGBA32）
		var u8:Dynamic = img.data;
		if (u8 == null) {
			SLog.log('font_atlas data 为 null!');
			return;
		}
		var len:Int = Std.int(imgW) * Std.int(imgH) * 4;
		pixels = haxe.io.Bytes.alloc(len);
		for (i in 0...len) pixels.set(i, u8[i]);
		SLog.log('font_atlas 像素快照完成 ' + len);
		// 字形元数据
		var jsonStr:String = lime.utils.Assets.getText("assets/font_atlas.json");
		meta = Json.parse(jsonStr);
		size = meta.size;
	}

	/** 首帧渲染时调用（GL 上下文已激活） */
	public function ensureTexture(gl:Dynamic):Void {
		if (textureId != null || pixels == null) return;
		textureId = gl.createTexture();
		gl.bindTexture(gl.TEXTURE_2D, textureId);
		GLUtil.uploadTexture(gl, gl.TEXTURE_2D, Std.int(imgW), Std.int(imgH), pixels);
		SLog.log('atlasTex err=' + gl.getError());
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
	}

	/** 画一行文字，返回实际宽度；scale = 目标字号 / 原始字号 */
	public function drawText(geo:Geo, text:String, x:Float, y:Float, scale:Float,
			r:Float, g:Float, b:Float, a:Float):Float {
		if (textureId == null) return 0;
		var cx = x;
		var chars:Dynamic = meta.chars;
		for (i in 0...text.length) {
			var ch = text.charAt(i);
			var m:Dynamic = Reflect.field(chars, ch);
			if (m == null) {
				cx += 10 * scale;
				continue;
			}
			var u1:Float = m.u / imgW, v1:Float = m.v / imgH;
			var u2:Float = (m.u + m.w) / imgW, v2:Float = (m.v + m.h) / imgH;
			var dx = cx + m.ox * scale;
			var dy = y + m.oy * scale;
			var dw = m.w * scale, dh = m.h * scale;
			geo.tQuad(dx, dy, dx + dw, dy, dx + dw, dy + dh, dx, dy + dh,
				u1, v1, u2, v2, r, g, b, a);
			cx += m.adv * scale;
		}
		return cx - x;
	}

	public function measure(text:String, scale:Float):Float {
		var cx = 0.0;
		var chars:Dynamic = meta.chars;
		for (i in 0...text.length) {
			var m:Dynamic = Reflect.field(chars, text.charAt(i));
			cx += (m != null ? m.adv : 10) * scale;
		}
		return cx;
	}
}
