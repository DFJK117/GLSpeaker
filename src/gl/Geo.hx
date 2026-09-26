package gl;

import lime.utils.Float32Array;

/**
 * 动态几何缓冲：一次性写入所有三角形，两个 drawArrays 完成（平色 + 文字）。
 * 顶点布局 flat:   x,y,r,g,b,a
 * 顶点布局 textured: x,y,u,v,r,g,b,a
 */
class Geo {

	public var flat:Float32Array;
	public var flatCount:Int = 0;

	public var tex:Float32Array;
	public var texCount:Int = 0;

	public function new() {
		flat = new Float32Array(65536);
		tex = new Float32Array(65536);
	}

	public function clear():Void {
		flatCount = 0;
		texCount = 0;
	}

	inline function ensure(arr:Float32Array, used:Int, need:Int):Void {
		if (used + need > arr.length) throw "Geo overflow: 请调大缓冲";
	}

	// ———————— flat ————————
	public inline function fv(x:Float, y:Float, r:Float, g:Float, b:Float, a:Float):Void {
		var o = flatCount;
		ensure(flat, o, 6);
		flat[o] = x; flat[o + 1] = y;
		flat[o + 2] = r; flat[o + 3] = g; flat[o + 4] = b; flat[o + 5] = a;
		flatCount += 6;
	}

	public inline function fQuad(x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float, x4:Float, y4:Float,
			r:Float, g:Float, b:Float, a:Float):Void {
		fv(x1, y1, r, g, b, a); fv(x2, y2, r, g, b, a); fv(x3, y3, r, g, b, a);
		fv(x1, y1, r, g, b, a); fv(x3, y3, r, g, b, a); fv(x4, y4, r, g, b, a);
	}

	public inline function fRect(x:Float, y:Float, w:Float, h:Float, r:Float, g:Float, b:Float, a:Float):Void {
		fQuad(x, y, x + w, y, x + w, y + h, x, y + h, r, g, b, a);
	}

	public inline function fTri(x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float,
			r:Float, g:Float, b:Float, a:Float):Void {
		fv(x1, y1, r, g, b, a); fv(x2, y2, r, g, b, a); fv(x3, y3, r, g, b, a);
	}

	public function fFan(cx:Float, cy:Float, radius:Float, seg:Int, r:Float, g:Float, b:Float, a:Float):Void {
		var step = Math.PI * 2 / seg;
		for (i in 0...seg) {
			var a1 = i * step, a2 = (i + 1) * step;
			fTri(cx, cy, cx + Math.cos(a1) * radius, cy + Math.sin(a1) * radius,
				cx + Math.cos(a2) * radius, cy + Math.sin(a2) * radius, r, g, b, a);
		}
	}

	public function fArc(cx:Float, cy:Float, radius:Float, seg:Int, start:Float, sweep:Float, width:Float,
			r:Float, g:Float, b:Float, a:Float):Void {
		var step = sweep / seg;
		for (i in 0...seg) {
			var a1 = start + i * step, a2 = a1 + step;
			var c1 = Math.cos(a1), s1 = Math.sin(a1);
			var c2 = Math.cos(a2), s2 = Math.sin(a2);
			fQuad(cx + c1 * radius, cy + s1 * radius,
				  cx + c2 * radius, cy + s2 * radius,
				  cx + c2 * (radius + width), cy + s2 * (radius + width),
				  cx + c1 * (radius + width), cy + s1 * (radius + width), r, g, b, a);
		}
	}

	/** 圆角矩形（UI 用） */
	public function fRoundRect(x:Float, y:Float, w:Float, h:Float, rad:Float,
			r:Float, g:Float, b:Float, a:Float):Void {
		var seg = 4;
		var corners = [[x + w - rad, y + rad, 0.0], [x + w - rad, y + h - rad, Math.PI * 0.5],
			[x + rad, y + h - rad, Math.PI], [x + rad, y + rad, Math.PI * 1.5]];
		// 中心
		fRect(x + rad, y + rad, w - rad * 2, h - rad * 2, r, g, b, a);
		// 四边
		fRect(x + rad, y, w - rad * 2, rad, r, g, b, a);
		fRect(x + rad, y + h - rad, w - rad * 2, rad, r, g, b, a);
		fRect(x, y + rad, rad, h - rad * 2, r, g, b, a);
		fRect(x + w - rad, y + rad, rad, h - rad * 2, r, g, b, a);
		// 四角
		for (c in corners) fFan(c[0], c[1], rad, seg, r, g, b, a);
	}

	// ———— Bytes 镜像（原生上传用）—————
	public var flatBytes:haxe.io.Bytes;
	public var texBytes:haxe.io.Bytes;

	public function syncBytes():Void {
		if (flatBytes == null) flatBytes = haxe.io.Bytes.alloc(flat.length * 4);
		for (i in 0...flatCount) flatBytes.setFloat(i * 4, flat[i]);
		if (texBytes == null) texBytes = haxe.io.Bytes.alloc(tex.length * 4);
		for (i in 0...texCount) texBytes.setFloat(i * 4, tex[i]);
	}

	// ———————— textured（文字）———————
	public inline function tv(x:Float, y:Float, u:Float, v:Float, r:Float, g:Float, b:Float, a:Float):Void {
		var o = texCount;
		ensure(tex, o, 8);
		tex[o] = x; tex[o + 1] = y; tex[o + 2] = u; tex[o + 3] = v;
		tex[o + 4] = r; tex[o + 5] = g; tex[o + 6] = b; tex[o + 7] = a;
		texCount += 8;
	}

	public inline function tQuad(x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float, x4:Float, y4:Float,
			u1:Float, v1:Float, u2:Float, v2:Float, r:Float, g:Float, b:Float, a:Float):Void {
		tv(x1, y1, u1, v1, r, g, b, a); tv(x2, y2, u2, v1, r, g, b, a); tv(x3, y3, u2, v2, r, g, b, a);
		tv(x1, y1, u1, v1, r, g, b, a); tv(x3, y3, u2, v2, r, g, b, a); tv(x4, y4, u1, v2, r, g, b, a);
	}
}
