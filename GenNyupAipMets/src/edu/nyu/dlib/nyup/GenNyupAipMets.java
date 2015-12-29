package edu.nyu.dlib.nyup;

import org.apache.log4j.Logger;
import au.edu.apsr.mtk.base.*;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.IOException;
import java.net.FileNameMap;
import java.net.URI;
import java.net.URLConnection;
import java.security.MessageDigest;
import java.text.DecimalFormat;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Calendar;
import java.util.Collections;
import java.util.Date;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.TimeZone;

// @SuppressWarnings("unchecked")

public class GenNyupAipMets {

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

	static final String UNIVERSAL_PDF_REGEX = "Universal_PDF/\\d+\\.pdfa?$";

	static final String PAPERBACK_PRINT_PDF_REGEX
		= "Paperback_Print/\\d+\\.pdfa?$";

	static final String POD_PDF_REGEX = "POD_PDF/\\d+\\.pdfa?$";

	static final String CLOTH_PDF_REGEX = "Cloth_Originals/\\d+\\.pdfa?$";

	static final String WEB_PDF_REGEX = "WebPDF/\\d+\\.pdfa?$";

	static final String PRINT_PDF_REGEX = "Print_PDF/\\d+\\.pdfa?$";
	
	static final String COVER_PDF_REGEX = "Cover_PDF/\\d+\\.pdfa?$";

	static final String COVER_IMG_REGEX = "Cover.*\\.(jpe?g|tiff?)$";

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
	
	static METS mets;

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
			SimpleDateFormat df
				= new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'");
			Calendar cal = Calendar.getInstance(TimeZone.getTimeZone("UTC"));
			String currentTime = df.format(cal.getTime());	

			METSWrapper metsWrapper = new METSWrapper();
			mets = metsWrapper.getMETSObject();
			mets.setObjID(aipId);
			mets.setType("Text");

			MetsHdr metsHdr = mets.newMetsHdr();
			metsHdr.setCreateDate(currentTime);
        	metsHdr.setLastModDate(currentTime);
			metsHdr.setRecordStatus("Completed");

			Agent agent = metsHdr.newAgent();
			agent.setRole("CREATOR");
			agent.setType("INDIVIDUAL");
			agent.setName("Rasch, Rasan");
			metsHdr.addAgent(agent);

			agent = metsHdr.newAgent();
			agent.setRole("CUSTODIAN");
			agent.setType("ORGANIZATION");
			agent.setName("NYU DLTS");
			metsHdr.addAgent(agent);

			agent = metsHdr.newAgent();
			agent.setRole("DISSEMINATOR");
			agent.setType("ORGANIZATION");
			agent.setName("NYU DLTS");
			metsHdr.addAgent(agent);

			mets.setMetsHdr(metsHdr);

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
				DmdSec dmdSec = mets.newDmdSec();
				dmdSec.setID(createId("dmd", i + 1));
				addMdRef(dmdSec, dmdFile);
				mets.addDmdSec(dmdSec);
			}

			AmdSec amdSec = mets.newAmdSec();

			ArrayList<java.io.File> techmdFiles
				= getFileList(metaDir, techmdMatcher);
			log.debug("There are " + techmdFiles.size() + " TechMD files.");
			addTechMD(amdSec, techmdFiles, "techMD.");

			ArrayList<java.io.File> rmdFiles
				= getFileList(metaDir, rmdMatcher);
			for (int i = 0; i < rmdFiles.size(); i++) {
				java.io.File rmdFile = rmdFiles.get(i);
				RightsMD rightsMD = amdSec.newRightsMD();
				rightsMD.setID(basename(rmdFile));
				addMdRef(rightsMD, rmdFile);
				amdSec.addRightsMD(rightsMD);
			}

			ArrayList<java.io.File> digiprovFiles
				= getFileList(metaDir, digiprovMatcher);
			for (int i = 0; i < digiprovFiles.size(); i++) {
				java.io.File digiprovFile = digiprovFiles.get(i);
				DigiprovMD digiprovMD = amdSec.newDigiprovMD();
				digiprovMD.setID(basename(digiprovFile));
				addMdRef(digiprovMD, digiprovFile);
				amdSec.addDigiprovMD(digiprovMD);
			}
			
			mets.addAmdSec(amdSec);

			FileSec fileSec = mets.newFileSec();

			StructMap structMap = mets.newStructMap();
			structMap.setType("PHYSICAL");
			Div outerDiv = structMap.newDiv();

			TreeMap<String, Div> divMap = new TreeMap<String, Div>();
			divMap.put("0-images", outerDiv.newDiv());
			divMap.put("1-books",  outerDiv.newDiv());

			mets.setFileSec(fileSec);

			createFileGrpAndFptr(fileSec, divMap, dataDir,
				EPUB_REGEX, "EPUB");
			createFileGrpAndFptr(fileSec, divMap, dataDir,
				UNIVERSAL_PDF_REGEX, "UNIVERSAL");
			createFileGrpAndFptr(fileSec, divMap, dataDir,
				PAPERBACK_PRINT_PDF_REGEX, "PAPERBACK_PRINT");
			createFileGrpAndFptr(fileSec, divMap, dataDir,
				POD_PDF_REGEX, "PRINT_ON_DEMAND");
			createFileGrpAndFptr(fileSec, divMap, dataDir,
				CLOTH_PDF_REGEX, "CLOTH_ORIGINAL");
			createFileGrpAndFptr(fileSec, divMap, dataDir,
				WEB_PDF_REGEX, "WEB");
			createFileGrpAndFptr(fileSec, divMap, dataDir,
				PRINT_PDF_REGEX, "PRINT");
			createFileGrpAndFptr(fileSec, divMap, dataDir,
				COVER_PDF_REGEX, "COVER_PDF");
			createFileGrpAndFptr(fileSec, divMap, dataDir,
				COVER_IMG_REGEX, "COVER", true);

			int i = 0;
			for (Div innerDiv : divMap.values()) {
				innerDiv.setOrder(String.valueOf(i++));
				outerDiv.addDiv(innerDiv);
			}
			
			structMap.addDiv(outerDiv);
			mets.addStructMap(structMap);

			metsWrapper.validate();

			metsWrapper.write(new FileOutputStream(outputFile));
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


	static void createFileGrpAndFptr(FileSec fileSec,
			TreeMap<String, Div> divMap,
			java.io.File dir,
			String regex,
			String grpName) throws Exception {
		createFileGrpAndFptr(fileSec, divMap, dir, regex, grpName, false);
	}


	static void createFileGrpAndFptr(FileSec fileSec,
			TreeMap<String, Div> divMap,
			java.io.File dir,
			String regex,
			String grpName,
			boolean isCoverImg) throws Exception {

		Matcher matcher
			= Pattern.compile(regex, Pattern.CASE_INSENSITIVE).matcher("");

		String grpNameLower = grpName.toLowerCase();

		ArrayList<java.io.File> fileList = getFileList(dir, matcher);

		log.debug("There are " + fileList.size() + " " + grpName + " files.");

		if (fileList.isEmpty()) {
			log.warn(grpName + " file list is empty.");
			return;
		}

		FileGrp outerFileGrp = fileSec.newFileGrp();
		outerFileGrp.setID(grpNameLower);
		outerFileGrp.setUse(grpName);

		FileGrp masterFileGrp = outerFileGrp.newFileGrp();
		masterFileGrp.setUse("MASTER");

		FileGrp originalFileGrp = outerFileGrp.newFileGrp();
		originalFileGrp.setUse("ORIGINAL");
		
		for (int i = 0; i < fileList.size(); i++) {

			java.io.File aipFile = fileList.get(i);
			String aipFileName = aipFile.getName();
			String id = genId(aipFile, true); 

			log.debug("aip file: " + aipFile.getCanonicalPath());
			
			File file;
			if (aipFileName.endsWith("pdfa")) {
				file = masterFileGrp.newFile();
				masterFileGrp.addFile(file);
			} else {
				file = originalFileGrp.newFile();
				originalFileGrp.addFile(file);
			}

			file.setID(id);
			file.setChecksumType("SHA-1");
			file.setChecksum(getChecksum(aipFile));
			file.setMIMEType(getMimeType(aipFile));

			FLocat fLocat = file.newFLocat();
			fLocat.setLocType("URL");
			fLocat.setHref(getRelPathToRoot(aipFile));
			file.addFLocat(fLocat);

			Div innerDiv;
			if (isCoverImg) {
				innerDiv = divMap.get("0-images");
			} else {
				innerDiv = divMap.get("1-books");
			}
			
			Fptr fptr = innerDiv.newFptr();
			fptr.setFileID(id);
			innerDiv.addFptr(fptr);
		}

		outerFileGrp.addFileGrp(masterFileGrp);
		outerFileGrp.addFileGrp(originalFileGrp);
		fileSec.addFileGrp(outerFileGrp);
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
			String idPrefix) throws Exception {

		if (fileList.isEmpty()) {
			return;
		}

		for (int i = 0; i < fileList.size(); i++) {
			java.io.File techmdFile = fileList.get(i);
			TechMD techMD = amdSec.newTechMD();
			techMD.setID(idPrefix + genId(techmdFile, false));
			addMdRef(techMD, techmdFile);
			amdSec.addTechMD(techMD);
		}

	}


	static void addMdRef(MdSec mdSec, java.io.File mdFile)
			throws Exception {

		String mdFileName = mdFile.getName();

		MdRef mdRef = mdSec.newMdRef();
		mdRef.setLocType("URL");
		mdRef.setHref(getRelPathToRoot(mdFile));
		mdRef.setChecksumType("SHA-1");
		mdRef.setChecksum(getChecksum(mdFile));
		mdRef.setMIMEType(getMimeType(mdFile));

		mdtypeMatcher.reset(mdFileName);
		otherMdtypeMatcher.reset(mdFileName);

		if (mdFileName.matches(".*_digiprov.xml$")) {
			mdRef.setMDType("PREMIS");
		} else if (mdtypeMatcher.find()) {
			mdRef.setMDType(mdtypeMatcher.group(1).toUpperCase());
		} else {
			mdRef.setMDType("OTHER");
			if (otherMdtypeMatcher.find()) {
				mdRef.setOtherMDType(otherMdtypeMatcher.group(1).toUpperCase());
			} else {
				mdRef.setOtherMDType("UNKNOWN");
			}
		}
		
		mdSec.setMdRef(mdRef);
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
		id = id.replaceAll("[/.]", "_");
		log.debug("ID: " + id);
		return id;
	}


}

