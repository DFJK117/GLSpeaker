package gl;

/**
 * 原生崩溃定位日志：每个阶段追加到 exe 旁边 glspeaker.log
 */
class SLog {

	public static var path:String = "glspeaker.log";

	public static function log(msg:String):Void {
		#if sys
		var line = Date.now().toString().substr(11, 8) + " " + msg + "\n";
		try {
			var f = sys.io.File.append(path, false);
			f.writeString(line);
			f.close();
		} catch (e:Dynamic) {}
		// 双写：固定绝对路径，便于远程诊断直接读取
		try {
			var f2 = sys.io.File.append("E:////GLSpeaker-out////user-glspeaker.log", false);
			f2.writeString(line);
			f2.close();
		} catch (e:Dynamic) {}
		#end
	}
}
