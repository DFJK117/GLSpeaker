package gl;

import haxe.Json;
import lime.graphics.opengl.GL;
import lime.graphics.opengl.GLTexture;
import lime.graphics.Image;
import lime.utils.Assets;

/**
 * 字体图集：tools/gen_font_atlas.py 预生成的 PNG + JSON。
 * drawText 把每个字符作为 UV 四边形推入 Geo.tex。
 */
class FontAtlas {

	public var textureId:GLTexture;
	public var imgW:Float = 1;
	public var imgH:Float = 1;

	var meta:Dynamic;
	var size:Float;
	var img:Image;

	public function new() {
		img = Assets.getImage("assets/font_atlas.png");
		if (img != null) {
			imgW = img.width;
			imgH = img.height;
		} else {
			trace('font_atlas.png 缺失');
		}
		var jsonStr:String = Assets.getText("assets/font_atlas.json");
		meta = Json.parse(jsonStr);
		size = meta.size;
	}

	/** 首帧渲染时调用（GL 上下文已激活） */
	public function ensureTexture():Void {
		if (textureId != null || img == null) return;
		{
			var img0:Image = img;
			GL.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.LINEAR);
			GL.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.LINEAR);
			GL.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, GL.CLAMP_TO_EDGE);
			GL.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, GL.CLAMP_TO_EDGE);
			img = null; // 释放引用
		}
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
