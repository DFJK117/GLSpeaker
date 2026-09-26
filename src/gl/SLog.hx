package gl;

/**
 * 原生崩溃定位日志：每个阶段追加到 exe 旁边 glspeaker.log
 */
class SLog {

	public static var path:String = "glspeaker.log";

	public static function log(msg:String):Void {
		#if sys
		try {
			var f = sys.io.File.append(path, false);
			f.writeString(Date.now().toString().substr(11, 8) + " " + msg + "\n");
			f.close();
		} catch (e:Dynamic) {}
		#end
	}
}
