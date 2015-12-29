package edu.nyu.dlib.nyup;

import org.apache.log4j.Logger;
import edu.harvard.hul.ois.mets.*;
import edu.harvard.hul.ois.mets.helper.*;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.IOException;
import java.net.FileNameMap;
import java.net.URI;
import java.net.URLConnection;
import java.security.MessageDigest;
import java.text.DecimalFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@SuppressWarnings("unchecked")

public class GenNyupAipMetsHarvardToolkit {

	static final String DMD_REGEX = "_(onix|mods)\\.xml$";
	static Matcher dmdMatcher = Pattern.compile(DMD_REGEX).matcher("");

	static final String TECHMD_REGEX = "_(exiftool|jhove|pdftk)";
	static Matcher techmdMatcher = Pattern.compile(TECHMD_REGEX).matcher("");

	static final String DIGIPROV_REGEX = "digiprov";
	static Matcher digiprovMatcher
		= Pattern.compile(DIGIPROV_REGEX).matcher("");

	static final String RMD_REGEX = "rights";
	static Matcher rmdMatcher = Pattern.compile(RMD_REGEX).matcher("");

	static final String EPUB_REGEX = "ePub/\\d+\\.epub$";
	static Matcher epubMatcher = Pattern.compile(EPUB_REGEX).matcher("");

	static final String PAPERACK_PRINT_PDF_REGEX
		= "Paperback_Print/\\d+\\.pdfa?$";
	static Matcher paperbackPrintPdfMatcher
		= Pattern.compile(PAPERACK_PRINT_PDF_REGEX).matcher("");

	static final String POD_PDF_REGEX = "POD_PDF/\\d+\\.pdfa?$";
	static Matcher podPdfMatcher
		= Pattern.compile(POD_PDF_REGEX).matcher("");

	static final String CLOTH_PDF_REGEX = "Cloth_Originals/\\d+\\.pdfa?$";
	static Matcher clothPdfMatcher
		= Pattern.compile(CLOTH_PDF_REGEX).matcher("");

	static final String WEB_PDF_REGEX = "WebPDF/\\d+\\.pdfa?$";
	static Matcher webPdfMatcher = Pattern.compile(WEB_PDF_REGEX).matcher("");

	static final String PRINT_PDF_REGEX = "Print_PDF/\\d+\\.pdfa?$";
	static Matcher printPdfMatcher
		= Pattern.compile(PRINT_PDF_REGEX).matcher("");

	static final String COVER_JPG_REGEX = "Cover_JPE?G/\\d+\\.jpe?g$";
	static Matcher coverJpgMatcher
		= Pattern.compile(COVER_JPG_REGEX).matcher("");

	static final String MDTYPE_REGEX = ".*_(dc|ead|marc|mods)\\.xml$";
	static Matcher mdtypeMatcher = Pattern.compile(MDTYPE_REGEX).matcher("");

	static final String OTHER_MDTYPE_REGEX
		= ".*_(droid|exiftool|jhove|onix|pbcore|pdftk)\\.(txt|xml)$";
	static Matcher otherMdtypeMatcher
		= Pattern.compile(OTHER_MDTYPE_REGEX).matcher("");

	static Logger log = Logger.getLogger(GenNyupAipMets.class);

	static int aipDirNameLength = 0;
	static int metaDirNameLength = 0;
	static int dataDirNameLength = 0;

	public static void main(String[] args) {

		if (args.length != 4) {
			System.err
					.println("Usage: java GenNyupAipMets <aip id> <aip version> <aip directory> <output file>");
			System.exit(1);
		}

		String aipId = args[0];
		String aipVersion = args[1];
		String aipDirName = args[2];
		String outputFile = args[3];

		try {
			Date now = new Date();

			Mets mets = new Mets();
			mets.setOBJID(aipId);
			mets.setTYPE("Text");

			MetsHdr metsHdr = new MetsHdr();
			metsHdr.setCREATEDATE(now);
			metsHdr.setLASTMODDATE(now);
			metsHdr.setRECORDSTATUS("Completed");

			Agent agent = new Agent();
			Name name = new Name();
			agent.setROLE(Role.CREATOR);
			agent.setTYPE(Type.INDIVIDUAL);
			name.getContent().add(new PCData("Rasch, Rasan"));
			agent.getContent().add(name);
			metsHdr.getContent().add(agent);

			agent = new Agent();
			name = new Name();
			agent.setROLE(Role.CUSTODIAN);
			agent.setTYPE(Type.ORGANIZATION);
			name.getContent().add(new PCData("NYU DLTS"));
			agent.getContent().add(name);
			metsHdr.getContent().add(agent);

			agent = new Agent();
			name = new Name();
			agent.setROLE(Role.DISSEMINATOR);
			agent.setTYPE(Type.ORGANIZATION);
			name.getContent().add(new PCData("NYU DLTS"));
			agent.getContent().add(name);
			metsHdr.getContent().add(agent);

			mets.getContent().add(metsHdr);

			java.io.File aipDir = new java.io.File(aipDirName);
			if (!aipDir.isDirectory()) {
				log.fatal("aip directory " + aipDir + " isn't a directory.");
				System.exit(1);
			}

			String aipVersionDirName = aipDirName + "/files/" + aipVersion;

			java.io.File dataDir
				= new java.io.File(aipVersionDirName + "/data");	
			log.debug("data directory: " + dataDir);
			java.io.File metaDir
				= new java.io.File(aipVersionDirName + "/metadata");
			log.debug("metadata directory: " + metaDir);

			aipDirNameLength = aipDir.getCanonicalPath().length();
			metaDirNameLength = metaDir.getCanonicalPath().length();
			dataDirNameLength = dataDir.getCanonicalPath().length();

			ArrayList<java.io.File> dmdFiles
				= getFileList(metaDir, dmdMatcher);
			log.debug("There are " + dmdFiles.size() + " DMD files.");
			for (int i = 0; i < dmdFiles.size(); i++) {
				java.io.File dmdFile = dmdFiles.get(i);
				log.debug("DMD filename: " + dmdFile.getName());
				DmdSec dmdSec = new DmdSec();
				dmdSec.setID(createId("dmd", i + 1));
				MdRef mdRef = getMdRef(dmdFile);
				dmdSec.getContent().add(mdRef);
				mets.getContent().add(dmdSec);
			}

			ArrayList<java.io.File> techmdFiles
				= getFileList(metaDir, techmdMatcher);
			log.debug("There are " + techmdFiles.size() + " TechMD files.");
			AmdSec amdSec = new AmdSec();
			addTechMD(amdSec, techmdFiles, "techMD.");
			mets.getContent().add(amdSec);

			ArrayList<java.io.File> rmdFiles
				= getFileList(metaDir, rmdMatcher);
			for (int i = 0; i < rmdFiles.size(); i++) {
				java.io.File rmdFile = rmdFiles.get(i);
				RightsMD rightsMD = new RightsMD();
				rightsMD.setID(basename(rmdFile));
				MdRef mdRef = getMdRef(rmdFile);
				rightsMD.getContent().add(mdRef);
				amdSec.getContent().add(rightsMD);
			}

			ArrayList<java.io.File> digiprovFiles
				= getFileList(metaDir, digiprovMatcher);
			for (int i = 0; i < digiprovFiles.size(); i++) {
				java.io.File digiprovFile = digiprovFiles.get(i);
				DigiprovMD digiprovMD = new DigiprovMD();
				digiprovMD.setID(basename(digiprovFile));
				MdRef mdRef = getMdRef(digiprovFile);
				digiprovMD.getContent().add(mdRef);
				amdSec.getContent().add(digiprovMD);
			}

			FileSec fileSec = new FileSec();
			ArrayList<StructMap> structMapList = new ArrayList<StructMap>();

			createFileGrpAndStructMap(fileSec, structMapList, dataDir,
				epubMatcher, "EPUB");
			createFileGrpAndStructMap(fileSec, structMapList, dataDir,
				paperbackPrintPdfMatcher, "PAPERBACK_PRINT");
			createFileGrpAndStructMap(fileSec, structMapList, dataDir,
				podPdfMatcher, "PRINT_ON_DEMAND");
			createFileGrpAndStructMap(fileSec, structMapList, dataDir,
				clothPdfMatcher, "CLOTH_ORIGINAL");
			createFileGrpAndStructMap(fileSec, structMapList, dataDir,
				webPdfMatcher, "WEB");
			createFileGrpAndStructMap(fileSec, structMapList, dataDir,
				printPdfMatcher, "PRINT");
			createFileGrpAndStructMap(fileSec, structMapList, dataDir,
				coverJpgMatcher, "COVER");

			mets.getContent().add(fileSec);

			for (int i = 0; i < structMapList.size(); i++) {
				StructMap structMap = structMapList.get(i);
				mets.getContent().add(structMap);
			}

			mets.validate(new MetsValidator());

			mets.write(new MetsWriter(new FileOutputStream(outputFile)));
			log.info("Wrote " + outputFile);

		} catch (Exception e) {
			e.printStackTrace();
			System.exit(1);
		}
	}


	static String getChecksum(java.io.File datafile) throws Exception {

		MessageDigest md = MessageDigest.getInstance("SHA1");
		FileInputStream fis = new FileInputStream(datafile);
		byte[] dataBytes = new byte[1024];

		int nread = 0;

		while ((nread = fis.read(dataBytes)) != -1) {
			md.update(dataBytes, 0, nread);
		}
		byte[] mdbytes = md.digest();

		// convert the byte to hex format
		StringBuffer sb = new StringBuffer("");
		for (int i = 0; i < mdbytes.length; i++) {
			sb.append(Integer.toString((mdbytes[i] & 0xff) + 0x100, 16)
					.substring(1));
		}

		return sb.toString();
	}


	static void createFileGrpAndStructMap(FileSec fileSec,
			ArrayList<StructMap> structMapList,
			java.io.File dir,
			Matcher matcher,
			String grpName) throws Exception {

		String grpNameLower = grpName.toLowerCase();

		ArrayList<java.io.File> fileList = getFileList(dir, matcher);

		log.debug("There are " + fileList.size() + " " + grpName + " files.");

		if (fileList.isEmpty()) {
			log.warn(grpName + " file list is empty.");
			return;
		}

		FileGrp outerFileGrp = new FileGrp();
		outerFileGrp.setID(grpNameLower);
		outerFileGrp.setUSE(grpName);

		FileGrp masterFileGrp = new FileGrp();
		masterFileGrp.setUSE("MASTER");

		FileGrp originalFileGrp = new FileGrp();
		originalFileGrp.setUSE("ORIGINAL");
		
		StructMap structMap = new StructMap();
		structMap.setTYPE(grpName);

		Div outerDiv = new Div();
// 		outerDiv.setID(null);
// 		outerDiv.setADMID(null);

		for (int i = 0; i < fileList.size(); i++) {

			java.io.File aipFile = fileList.get(i);
			String aipFileName = aipFile.getName();

			log.debug("aip file: " + aipFile.getCanonicalPath());

			File file = new File();
// 			file.setID(createId(grpNameLower, i) + "_" + basename(aipFile));
			file.setID(genId(aipFile, true));
			file.setCHECKSUMTYPE(Checksumtype.SHA1);
			file.setCHECKSUM(getChecksum(aipFile));
			file.setMIMETYPE(getMimeType(aipFile));

			FLocat fLocat = new FLocat();
			fLocat.setLOCTYPE(Loctype.URL);
			fLocat.setXlinkHref(getRelPathToRoot(aipFile));

			file.getContent().add(fLocat);

			if (aipFileName.endsWith("pdfa")) {
				masterFileGrp.getContent().add(file);
			} else {
				originalFileGrp.getContent().add(file);
			}

			Fptr fptr = new Fptr();
// 			fptr.setFILEID(createId(grpNameLower, i) + "_" + basename(aipFile));
			fptr.setFILEID(genId(aipFile, true));
			Div innerDiv = new Div();
// 			innerDiv.setID("FOO");
			innerDiv.setORDER(i);
// 			innerDiv.setTYPE("FOO");
			innerDiv.getContent().add(fptr);
			outerDiv.getContent().add(innerDiv);
			
			structMap.getContent().add(outerDiv);
		}

		outerFileGrp.getContent().add(masterFileGrp);
		outerFileGrp.getContent().add(originalFileGrp);
		fileSec.getContent().add(outerFileGrp);
		
		structMapList.add(structMap);
	}


	/**
	 * Pad integer with leading zeros.
	 * 
	 * @param value
	 *            integer value to be padded
	 * @param length
	 *            minimum length of padded string
	 * @return zero-padded string
	 */
	static String zeroPad(int value, int length) {
		DecimalFormat df = new DecimalFormat();
		df.setMinimumIntegerDigits(length);
		// df.setGroupingUsed(false);
		return df.format(value);
	}


	static String createId(String prefix, int index) {
		return prefix + "_" + zeroPad(index, 3);
	}


	static void addTechMD(AmdSec amdSec, ArrayList<java.io.File> fileList,
			String idPrefix) throws IOException {

		if (fileList.isEmpty()) {
			return;
		}

		for (int i = 0; i < fileList.size(); i++) {
			java.io.File techmdFile = fileList.get(i);
			MdRef mdRef = getMdRef(techmdFile);
			TechMD techMD = new TechMD();
			techMD.setID(idPrefix + genId(techmdFile, false));
			techMD.getContent().add(mdRef);
			amdSec.getContent().add(techMD);
		}

	}


	static MdRef getMdRef(java.io.File mdFile) throws IOException {
		
		String mdFileName = mdFile.getName();

		MdRef mdRef = new MdRef();
		mdRef.setLOCTYPE(Loctype.URL);
		mdRef.setXlinkHref(getRelPathToRoot(mdFile));

		mdtypeMatcher.reset(mdFileName);
		otherMdtypeMatcher.reset(mdFileName);

		if (mdFileName.matches("_digiprov.xml$")) {
			mdRef.setMDTYPE(Mdtype.PREMIS);
		} else if (mdtypeMatcher.find()) {
			mdRef.setMDTYPE(new Mdtype(mdtypeMatcher.group(1).toUpperCase()));
		} else {
			mdRef.setMDTYPE(Mdtype.OTHER);
			if (otherMdtypeMatcher.find()) {
				mdRef.setOTHERMDTYPE(otherMdtypeMatcher.group(1).toUpperCase());
			} else {
				mdRef.setOTHERMDTYPE("UNKNOWN");
			}
		}

		return mdRef;

	}

	
	static ArrayList<java.io.File> getFileList(java.io.File dir,
			Matcher matcher) {
		ArrayList<java.io.File> fileList =  new ArrayList<java.io.File>();
		traverseDirTree(dir, fileList, matcher);
		Collections.sort(fileList);
		return fileList;
	}

	
	static void traverseDirTree(java.io.File dir,
			ArrayList<java.io.File> fileList,
			Matcher matcher) {
		if (dir.exists()) {
			if (dir.isDirectory()) {
				java.io.File[] children = dir.listFiles();
				for (int i = 0; i < children.length; i++) {
					traverseDirTree(children[i], fileList, matcher);
				}
			} else {
				log.trace("filename: " + dir.getName());
				matcher.reset(dir.getPath());
				if (matcher.find()) {
					log.trace("Found match for regex: " +  matcher.pattern());
					fileList.add(dir);
				}
			}
		}
	}


	static String getRelPathToRoot(java.io.File file) throws IOException {
		return file.getCanonicalPath().substring(aipDirNameLength + 1);
	}

	static String getRelPathToMetadata(java.io.File file) throws IOException {
		return file.getCanonicalPath().substring(metaDirNameLength + 1);
	}

	static String getRelPathToData(java.io.File file) throws IOException {
		return file.getCanonicalPath().substring(dataDirNameLength + 1);
	}

	
	static String getMimeType(java.io.File file) throws IOException {
		FileNameMap fileNameMap = URLConnection.getFileNameMap();
		String type = fileNameMap.getContentTypeFor(file.toURI().toString());
		if (type != null) {
			return type;
		} else if (file.getName().endsWith(".pdfa")) {
			return "application/pdf";
		} else {
			return "application/octet-stream";
		}
	}


	static String basename(java.io.File file) {
		String name = file.getName();
		int dot = name.lastIndexOf('.');
		String base = (dot == -1) ? name : name.substring(0, dot);
		return base;
	}


	static String genId(java.io.File file, boolean isData) throws IOException {
		String id = isData ?
			getRelPathToData(file) : getRelPathToMetadata(file);
// 		int dot = id.lastIndexOf('.');
// 		if (dot >= 0) {
// 			id = id.substring(0, dot);
// 		}
		id = id.replaceAll("[/.]", "_");
		log.debug("ID: " + id);
		return id;
	}


}

