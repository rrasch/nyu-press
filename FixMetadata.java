import java.util.List;
import org.apache.jempbox.xmp.XMPMetadata;
import org.apache.jempbox.xmp.XMPSchemaBasic;
import org.apache.jempbox.xmp.XMPSchemaDublinCore;
import org.apache.jempbox.xmp.XMPSchemaPDF;
import org.apache.pdfbox.tools.Version;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDDocumentCatalog;
import org.apache.pdfbox.pdmodel.PDDocumentInformation;
import org.apache.pdfbox.pdmodel.common.PDMetadata;

import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;


public class FixMetadata
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

			PDDocumentCatalog catalog = doc.getDocumentCatalog();
			PDMetadata meta = catalog.getMetadata();
			XMPMetadata metadata = meta.exportXMPMetadata();
			XMPSchemaBasic basic = metadata.getBasicSchema();
			XMPSchemaDublinCore dc = metadata.getDublinCoreSchema();
			XMPSchemaPDF pdf = metadata.getPDFSchema();

			PDDocumentInformation info = doc.getDocumentInformation();

			String pdfBoxVersion = "PDFBox " + Version.getVersion();

			String creatorTool = basic.getCreatorTool();
			if (creatorTool != null)
			{
				info.setCreator(creatorTool);
			}

			String pdfKeywords = pdf.getKeywords();
			String dictKeywords = info.getKeywords();
			System.err.println("pdf keywords: " + pdfKeywords);
			System.err.println("dict keywords: " + dictKeywords);
			if (pdfKeywords != null)
			{
				info.setKeywords(pdfKeywords);
			}

			if (dc.getCreators() == null)
			{
				System.err.println("Adding missing dc.creator...");
				dc.addCreator(pdfBoxVersion);
			}

			String author = info.getAuthor();
			String creator = dc.getCreators().get(0);
			System.err.println("Author: [" + author + "]");
			System.err.println("Creator: [" + creator + "]");

			dc.removeCreator(creator);
			creator = creator.trim();
			dc.addCreator(creator);

			if (!creator.equals(author))
			{
				info.setAuthor(creator);
			}

			String title = info.getTitle();
			String dcTitle = dc.getTitle();
			System.err.println("Title: '" + title + "'");
			System.err.println("dc.title: '" + dcTitle + "'");
			if (dcTitle != null)
			{
				dcTitle = dcTitle.trim();
			}
			info.setTitle(dcTitle);
			dc.setTitle(dcTitle);

			String description = dc.getDescription();
			if (description == null || description.equals("()"))
			{
				description = pdfBoxVersion;
			}

			Element root = dc.getElement();
			NodeList nodes = root.getElementsByTagName("dc:description");
			if (nodes.getLength() > 0)
			{
				Element elem = (Element) nodes.item(0);
				root.removeChild(elem);
			}
			Element dcDescElem
			    = root.getOwnerDocument().createElement("dc:description");
			root.appendChild(dcDescElem);

			info.setSubject(description);
			dc.setDescription(description);

			meta.importXMPMetadata(metadata);

			doc.save(args[1]);
		}
		catch (Exception ex)
		{
			System.err.println("Error fixing metadata for '"
			                   + args[0] + "': " + ex);
			ex.printStackTrace();
			System.exit(1);
		}
	}

	private static void usage()
	{
		System.err.println(
		    "Usage: java FixMetadata [input file] [output_file]");
	}

}

