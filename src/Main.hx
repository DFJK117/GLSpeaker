import audio.AudioEngine;
import gl.GLRenderer;
import lime.app.Application;
import StringTools;
import lime.ui.KeyCode;
import lime.ui.KeyModifier;
import lime.ui.MouseButton;
import ui.Panel;

/**
 * GLSpeaker —— 声音可视化（Haxe + Lime，全 OpenGL 渲染）
 * 还原原 Android 版 (yzrilyzr.blplayer)：
 *   背景图 / 左右 RMS 喇叭鼓动 / 圆形频谱 / 中心喇叭(果冻缩放) / Hz 读数
 * 已按需求：无粒子、无波浪线条；果冻缩放与频谱全 GPU；FFT 后台线程。
 */
class Main extends Application {

	var state:VizState;
	var engine:AudioEngine;
	var renderer:GLRenderer;
	var panel:Panel;
	var lastStamp:Float = 0;

	public function new() {
		super();
	}

	override public function onWindowCreate():Void {
		// 窗口/事件先就位；资源初始化等 onPreloadComplete（否则 default 库未加载会报错）
		state = new VizState();
		engine = new AudioEngine(state);
		lastStamp = haxe.Timer.stamp();
		window.onRender.add(onRenderFrame);
	}

	override public function onPreloadComplete():Void {
		try {
		renderer = new GLRenderer(state);
		panel = new Panel(state, engine);
		layoutPanel();

		#if sys
		// ① 命令行参数（把音乐文件拖到 exe 上）
		var args = Sys.args();
		for (a in args) {
			var low = a.toLowerCase();
			if (StringTools.endsWith(low, ".mp3") || StringTools.endsWith(low, ".ogg") || StringTools.endsWith(low, ".wav")
				|| StringTools.endsWith(low, ".flac") || StringTools.endsWith(low, ".m4a")) {
				engine.loadFile(a);
				break;
			}
		}
		// ② exe 同级 music/ 文件夹
		if (engine.playlist.length == 0 && engine.playlistIndex < 0) engine.scanMusicFolder();
		#end
		} catch (e:Dynamic) {
			logCrash('preload: ' + Std.string(e));
		}
	}

	static function logCrash(msg:String):Void {
		trace(msg);
		#if sys
		try sys.io.File.saveContent("glspeaker-crash.log", Date.now().toString() + " " + msg) catch (e:Dynamic) {};
		#end
	}

	function layoutPanel():Void {
		panel.x = window.width - Panel.W - 14;
		panel.y = 14;
	}

	override function onWindowResize(w:Int, h:Int):Void layoutPanel();

	// ———————— 主循环 ————————
	function onRenderFrame(context:lime.graphics.RenderContext):Void {
		if (renderer == null || panel == null) return; // 资源尚未预加载完成
		// 绑定本帧的实例 GL 上下文（native=gl / web=webgl）
		#if lime_webgl
		renderer.gl = context.webgl;
		#else
		renderer.gl = context.gl;
		#end
		if (renderer.gl == null) return; // 画布降级等无 GL 环境：跳过渲染
		var now = haxe.Timer.stamp();
		var dt = now - lastStamp;
		lastStamp = now;

		// 音频推进 + 分析同步
		engine.update();
		engine.sync();

		// UI 先画（同一几何缓冲），再画场景
		renderer.clearFrame();
		panel.draw(renderer.getGeo(), renderer.getFont(), state.playing, state.fileName);

		// Hz 读数（原版右上角 %dHz）
		var hz = Std.int(state.maxFreq) + "Hz";
		renderer.getFont().drawText(renderer.getGeo(), hz, 12, 10, 0.5, 1, 1, 1, 0.95);
		// 品牌水印（原版底部 yzr 位置）
		var brand = "GLSpeaker";
		var bw = renderer.getFont().measure(brand, 0.6);
		renderer.getFont().drawText(renderer.getGeo(), brand,
			window.width / 2 - bw / 2, window.height - 46, 0.6, 1, 1, 1, 0.13);

		renderer.draw(window.width, window.height, dt);
	}

	// ———————— 输入（Application 虚方法覆写）————————
	override public function onMouseDown(x:Float, y:Float, _:MouseButton):Void panel.mouseDown(x, y);
	override public function onMouseMove(x:Float, y:Float):Void panel.mouseMove(x, y);
	override public function onMouseUp(x:Float, y:Float, _:MouseButton):Void panel.mouseUp(x, y);

	override public function onKeyDown(code:KeyCode, mod:KeyModifier):Void {
		switch (code) {
			case KeyCode.SPACE:
				if (state.playing) engine.pause(); else engine.play();
			case KeyCode.LEFT:
				#if sys engine.next(-1); #end
			case KeyCode.RIGHT:
				#if sys engine.next(1); #end
			case KeyCode.O:
				engine.browse();
			default:
		}
	}
}
