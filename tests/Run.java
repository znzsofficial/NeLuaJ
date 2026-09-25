import org.luaj.Globals;
import org.luaj.LuaValue;
import org.luaj.lib.jse.JsePlatform;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * 行为测试驱动：在 JVM 上直接执行一个 Lua 测试脚本。
 *
 * 装载前根据脚本位置推导项目根（<root>/tests/*.lua），把全局 ASSETS
 * 指向 <root>/app/src/main/assets/，测试脚本用它拼接被测模块路径；
 * 推导失败时回退为相对路径（cwd 须为项目根）。
 *
 * 输出约定：脚本自行打印 PASS/FAIL 与 ALL-PASS，失败时 os.exit(1)。
 */
public class Run {
    public static void main(String[] args) throws Exception {
        Globals globals = JsePlatform.standardGlobals();
        Path root = Paths.get(args[0]).toAbsolutePath().normalize().getParent().getParent();
        if (root != null && Files.isDirectory(root.resolve("app/src/main/assets"))) {
            globals.set("ASSETS", root.resolve("app/src/main/assets").toString().replace('\\', '/') + "/");
        } else {
            globals.set("ASSETS", "app/src/main/assets/");
        }
        try (InputStreamReader reader = new InputStreamReader(new FileInputStream(args[0]), "UTF-8")) {
            LuaValue chunk = globals.load(reader, args[0]);
            chunk.call();
        }
        System.out.println("RUN-DONE");
    }
}
