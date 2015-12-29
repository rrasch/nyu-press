import java.util.List;
import java.util.Map;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDDocumentCatalog;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.font.PDFont;


public class FontInfo
{

	public static void main(String[] args) throws Exception
	{
		PDDocument doc = null;
		if (args.length != 1)
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
				System.err.println("Page: " + (i + 1));
				PDPage page = (PDPage) allPages.get(i);
				Map<String, PDFont> pageFonts
				    = page.getResources().getFonts();

				for (Map.Entry<String, PDFont> entry : pageFonts.entrySet())
				{
					PDFont font = entry.getValue();
					System.err.println("  Font: " + font.getBaseFont());
				}
			}
		}
		catch (Exception ex)
		{
			System.err.println("Error parsing pdf: " + ex);
		}
		finally
		{
			if (doc != null)
			{
				doc.close();
			}
		}
	}

	private static void usage()
	{
		System.err.println(
		    "Usage: java CheckFonts [input file]");
	}

}

