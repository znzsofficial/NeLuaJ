import org.luaj.Globals;
import org.luaj.compiler.LuaC;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;

/**
 * 批量语法检查：对每个给定的 Lua 文件做 load 编译验证。
 * 用法：java -noverify -cp "<luajpp.jar>;tests/out" SyntaxCheck <file.lua> [...]
 */
public class SyntaxCheck {
  public static void main(String[] args) throws Exception {
    Globals g = new Globals();
    LuaC.install(g);
    boolean allOk = true;
    for (String path : args) {
      byte[] bytes = Files.readAllBytes(Paths.get(path));
      String src = new String(bytes, StandardCharsets.UTF_8);
      try {
        g.load(src, "@" + path);
        System.out.println("OK   " + path);
      } catch (Throwable t) {
        allOk = false;
        System.out.println("FAIL " + path + " : " + t.getMessage());
      }
    }
    System.out.println(allOk ? "ALL OK" : "FAILURES PRESENT");
    if (!allOk) System.exit(1);
  }
}
