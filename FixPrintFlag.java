import java.util.List;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.interactive.annotation.PDAnnotation;


public class FixPrintFlag
{

	public static void main(String[] args) throws Exception
	{
		PDDocument doc = null;
		if (args.length != 2)
		{
			usage();
			System.exit(1);
		}

		try
		{
			doc = PDDocument.load(args[0]);
			List allPages = doc.getDocumentCatalog().getAllPages();
			for (int i = 0; i < allPages.size(); i++)
			{
				PDPage page = (PDPage)allPages.get(i);
				List annotations = page.getAnnotations();
				for (int j = 0; j < annotations.size(); j++)
				{
					PDAnnotation annot = (PDAnnotation)annotations.get(j);
					if (!annot.isPrinted())
					{
						System.out.println("setting print flag...");
						annot.setPrinted(true);
					}
				}
			}
			doc.save(args[1]);
			doc.close();
		}
		catch (Exception ex)
		{
			System.err.println("Error fixing annotations for '"
			                   + args[0] + "': " + ex);
			ex.printStackTrace();
			System.exit(1);
		}
	}

	private static void usage()
	{
		System.err.println(
		    "Usage: java FixPrintFlag [input file] [output_file]");
	}

}

