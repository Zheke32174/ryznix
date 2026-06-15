import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import ghidra.util.task.ConsoleTaskMonitor;
import java.io.*;
public class decompile_export extends GhidraScript {
    public void run() throws Exception {
        DecompInterface ifc = new DecompInterface();
        ifc.openProgram(currentProgram);
        FunctionManager fm = currentProgram.getFunctionManager();
        StringBuilder sb = new StringBuilder("// === Ghidra-decompiled C ===\n");
        int n = 0;
        for (Function f : fm.getFunctions(true)) {
            String nm = f.getName();
            if (nm.equals("_start") || nm.startsWith("_") || nm.equals("frame_dummy") || nm.equals("abort")) continue;
            DecompileResults res = ifc.decompileFunction(f, 60, new ConsoleTaskMonitor());
            if (res.decompileCompleted()) { sb.append(res.getDecompiledFunction().getC()).append("\n"); n++; }
        }
        PrintWriter pw = new PrintWriter(new File("/data/data/com.termux/files/home/re-tools/decompiled.c"));
        pw.write(sb.toString()); pw.close();
        println("GHIDRA_DECOMPILED " + n + " functions");
    }
}
