import com.android.ide.common.internal.ExecutorSingleton;
import com.android.ide.common.internal.PngCruncher;
import com.android.ide.common.res2.MergedResourceWriter;
import com.android.ide.common.res2.MergingException;
import com.android.ide.common.res2.ResourceMerger;
import com.android.ide.common.res2.ResourceSet;
import com.android.utils.StdLogger;
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;

public class MergeCheck {
  private static final PngCruncher COPY = new PngCruncher() {
    @Override
    public int start() {
      return 0;
    }

    @Override
    public void crunchPng(int key, File from, File to) {
      try {
        Files.copy(from.toPath(), to.toPath(), StandardCopyOption.REPLACE_EXISTING);
      } catch (IOException e) {
        throw new RuntimeException(e);
      }
    }

    @Override
    public void end(int key) {}
  };

  public static void main(String[] args) {
    boolean merged;
    try {
      merged = merge(new File(args[0]), args);
    } finally {
      ExecutorSingleton.shutdown();
    }
    if (!merged) {
      System.exit(1);
    }
  }

  private static boolean merge(File output, String[] args) {
    ResourceMerger merger = new ResourceMerger();
    StdLogger logger = new StdLogger(StdLogger.Level.WARNING);
    try {
      for (int i = 1; i < args.length; i++) {
        ResourceSet resources = new ResourceSet(new File(args[i]).getParentFile().getName());
        resources.addSource(new File(args[i]));
        resources.loadFromFiles(logger);
        merger.addDataSet(resources);
      }
      merger.mergeData(new MergedResourceWriter(output, COPY, false, false, null), false);
      System.out.println("Merged " + (args.length - 1) + " resource directories");
      return true;
    } catch (MergingException e) {
      System.err.println(e.getMessage());
      return false;
    }
  }
}
