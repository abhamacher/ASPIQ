#@ String (visibility=MESSAGE, value="Choose the images to be processed:") topMsg
#@ File (label = "Input directory", style = "directory") input
#@ File (label = "Output directory", style = "directory") output
#@ String (label = "File suffix", value = ".czi") suffix
#@ Boolean(label = "Continue from manual breakpoint", value = false) continueBP
#@ Boolean(label = "Show all channels for validation", value = false) allWindows
#@ Boolean(label = "Live Cell Imaging", value = false) LiveCell
#@ String (visibility=MESSAGE, value="Color allocation per channel for RGB output:") colMsg
#@ String(label = "C1", choices={"blue", "red", "green", "gray", "cyan", "magenta", "yellow"}, style="listBox") setChan1
#@ String(label = "C2", choices={"green", "red", "blue", "gray", "cyan", "magenta", "yellow"}, style="listBox") setChan2
#@ String(label = "C3", choices={"red", "green", "blue", "gray", "cyan", "magenta", "yellow"}, style="listBox") setChan3
#@ String(label = "(optional) C4", choices={"gray", "red", "green", "blue", "cyan", "magenta", "yellow"}, style="listBox") setChan4
#@ String (visibility=MESSAGE, value="Settings for ROI detection:") scriptMsg
#@ String (label = "Allowed Circularity", value = "0.05-1.00") set_circularity
#@ String(label = "Detect ROI based on:", choices={"merged channels", "single channel"}, style="radioButtonHorizontal") roiDetect
#@ String(label = "If single channel detection, use:", choices={"C1", "C2", "C3", "C4"}, style="listBox") setRoiChan
#@ String(label = "Segmentation Threshold:", choices={"Otsu", "Li"}, style="listBox") setSegmentThr
#@ String (visibility=MESSAGE, value="Note: Standard is Otsu, Li preferred for Live Cell Imaging") SegThrMsg
#@ Boolean(label = "Gaussian Blur Filter", value = false) set_gaussianFilter
#@ Double (label = "Gaussian Sigma", value = "2.0") set_gaussianSigma
#@ Boolean(label = "Histogram mode scaling", value = false) set_histoscale
#@ Boolean(label = "Slight Background Substraction", value = false) BGsubstract
#@ String(label = "If BG substraction, on channel:", choices={"C1", "C2", "C3", "C4", "all"}, style="listBox") setBGsubChan

/* 	Last update: 	28th February 2020 
 *	Script author: 	Anna Hamacher, HHU
 *	Modification:	Laura Wörmeyer, HHU (added line 74, sum slices for apotome images)
 *	
 *	Macro to process multiple images in a folder to 
 *	- automatically segment the image (detect the pancreatic islets)
 *	- in case of faulty segmentation, allow a manual correction  
 *	- re-run this macro to save ROIs after manual correction
 *	So far, apotome images can cause problems, if the bio-format importer of Fiji fails to stitch the tiles. 
 *	After completion of the ROI setting, the ASPIQ_Measure Macro needs to be run.
 */

// Check if input and output directories are different
if (input == output) {
	showMessage("Please choose an output directory that differs from the input directory and re-run the script. Script cancelled...");
	exit();
}

// General settings
separator = File.separator;
myChan = newArray(setChan1, setChan2, setChan3, setChan4);

// Main function
processFolder(input);

function processFolder(input) {
	list = getFileList(input);
	Array.sort(list); 
	for (i = 0; i < list.length; i++) {
		// ignore subfolders for processing
		if(endsWith(list[i], suffix) && !(File.isDirectory(input + separator + list[i])))
			if (i == 0 && continueBP) {
				saveROI(input, output, list[i]);
			} else {
				processFile(input, output, list[i]);
			}
	}
}

function processFile(input, output, file) {
	print("Processing: " + input + separator + file);
	
	run("Bio-Formats Importer", "open=[" + input + separator + file + "] autoscale color_mode=Composite rois_import=[ROI manager] view=Hyperstack stack_order=XYCZT stitch_tiles series_1");
	imageTitle = getTitle(); // needed for more than 1 tile (string incl. "#1")
	imageId = getImageID(); 
	totalSlices = nSlices();

	// Perform max intensity projection in case of live cell z-stack images
	if (LiveCell && totalSlices > 4) {
		run("Z Project...", "projection=[Max Intensity]");
		run("Z Project...", "projection=[Sum Slices]"); 
		Stack.setDisplayMode("composite");
		totalSlices = nSlices();
		close(imageTitle);
		selectWindow("MAX_" + imageTitle);
		rename(imageTitle);
	}

	// Decision of ROI detection on merged channels or a single channel
	if (roiDetect == "single channel") {
		run("Duplicate...", "duplicate channels=" + substring(setRoiChan, 1) + " title=[Working Copy "+ setRoiChan + "]");
	}	
	// Clear ROIs
	roiManager("reset");
	selectWindow(imageTitle);
	// Keep original image open for cross-reference
	run("Duplicate...", "duplicate"); 
	selectWindow(imageTitle);
	// Change format to 8-bit
	run("8-bit"); 
	run("Split Channels");
	for (i=1; i <= totalSlices ; i++)  {
		selectWindow("C" + i + "-" + imageTitle);
		run("8-bit");
		// Improve contrast based on histogram mode in merged RGB image
		// Useful in case of stainings with much background noise (e.g. CD45)
		if (set_histoscale) {
			List.setMeasurements; 
			// Get value "mode" and "max" from histogram function
			histogramMode = List.getValue("Mode"); 
			histogramMax = List.getValue("Max"); 		
			setMinAndMax(histogramMode, histogramMax);
		}

		// Perform a slight background substraction in case of very noisy stainings
		if (BGsubstract) {
			if (setBGsubChan == "all" || substring(setBGsubChan, 1) == i) {
				run("Subtract Background...", "rolling=150");
			}
		}
	}
	// System colours: C1=red, C2=green, C3=blue, C4=gray, C5=cyan, C6=magenta, C7=yellow
	// Color assignment for RGB output image
	sysChan = newArray(myChan.length);
	for (c = 0; c < myChan.length; c++ ){
		if (myChan[c] == "red") { sysChan[c] = "c1"; }				
		else if (myChan[c] == "green") { sysChan[c] = "c2"; } 		
		else if (myChan[c] == "blue") { sysChan[c] = "c3"; } 		
 		else if (myChan[c] == "gray") { sysChan[c] = "c4"; }		
		else if (myChan[c] == "cyan") { sysChan[c] = "c5"; }		
		else if (myChan[c] == "magenta") { sysChan[c] = "c6"; }	 	
		else if (myChan[c] == "yellow") { sysChan[c] = "c7";}	 	
	}
	// Merging channels to RGB image for ROI detection
	if (totalSlices == 3) { // Merge only channel 1-3
		run("Merge Channels...", sysChan[0] + "=[C1-" + imageTitle + "] " + sysChan[1] + "=[C2-" + imageTitle + "] " + sysChan[2] + "=[C3-" + imageTitle + "] keep");
	} else { //merge channel 1-4
		run("Merge Channels...", sysChan[0] + "=[C1-" + imageTitle + "] " + sysChan[1] + "=[C2-" + imageTitle + "] " + sysChan[2] + "=[C3-" + imageTitle + "] " + sysChan[3] + "=[C4-" + imageTitle + "] keep");
	}
	if (roiDetect == "single channel") {
		selectWindow("Working Copy "+ setRoiChan);
	} else {
		selectWindow("RGB");
		run("Duplicate...", "title=[Working Copy of RGB]");
		selectWindow("Working Copy of RGB");
	}

	// Thresholding with filtering and noise reduction
	run("8-bit");
	run("Enhance Contrast...", "saturated=0.3");
	if (set_gaussianFilter) {
		run("Gaussian Blur...", "sigma=" + set_gaussianSigma + " scaled");
	}
	
	setOption("BlackBackground", true);
	setAutoThreshold(setSegmentThr + " dark");
	run("Convert to Mask");
	run("Remove Outliers...", "radius=5 threshold=50 which=Bright");
	run("Fill Holes");
	/*if (LiveCell) {
			run("Watershed");
	};*/
	run("Analyze Particles...", "size=1200-Inifity circularity=" + set_circularity + " exclude include add");
		
	nROIs = roiManager("count");
	// Run watershed if no ROI detected (e.g. touching edges, lower circularity)
	if (nROIs == 0) {
		print ("Invalid operation, no ROI defined, trying Watershed!"); // Debug
		run("Watershed");
		run("Analyze Particles...", "size=900-Inifity circularity=" + set_circularity + " exclude include add");
		// Re-check the number of ROIs after watershed
		nROIs = roiManager("count");
	}

	// Use function Windows > Tile for the user to see all images at the same time for confirmation of ROIs
	if (allWindows) {
		run("Tile"); 
	}
	// End the automated islet detection, present result to the user for approval
	selectWindow("RGB");
	roiManager("Deselect");
	roiManager("Show All");
	
	// Ask user if ROIs are ok or need manual correction
	if (getBoolean("Are the suggested ROIs ok?")) {
		showMessage("Saving ROIs and overlay tiff...");
		saveROI(input, output, file);
		}
	else {
		showMessage("Please adjust the ROIs manually and re-run the script with <continue from manual breakpoint = yes>");
		exit(); // End macro for manual correction
	}
}

function saveROI(input, output, file) {

	setBatchMode(true);
	resultDir = output + separator + file + "_results"; 
	// Create the image specific result directory, if it doesn't exist yet
	if (!File.isDirectory(resultDir)) {
		File.makeDirectory(resultDir); 
	}
	
	// Save RGB-Overlay for easier scroll through
	// roiManager("Update") needs to be done while editing ROIs manually!
	selectWindow("RGB");
	// Make sure only the updated existing ROI(s) gets flattened
	roiManager("Deselect");
	roiManager("Show All");
	roiManager("Show None");
	roiManager("Show All");
	run("From ROI Manager");
	run("Flatten");
	selectWindow("RGB-1");
	saveAs("Tiff", resultDir + separator + file + "_RGB-Overlay.tif");
	
	// Save all ROIs to zip for later reference
	roiManager("Deselect");
	roiManager("Save", resultDir + separator + file + "_RoiSet.zip");
	
	// Move the original image to the result subfolder, proceed with the list of images in the main directory
	File.rename(input + separator + file, resultDir + separator + file); 

	saveScriptSettings(resultDir, file);

	setBatchMode(false);
	run("Close All");
}

function saveScriptSettings (resultDir, file) {

	logSettings = File.open(resultDir + separator + file + "_settings.txt");

	print(logSettings, "PARAMETER \t\t\t\t VALUE");
	print(logSettings, "===================================================================================================");
	print(logSettings, "Filename \t\t\t\t" + file);
	print(logSettings, "Live Cell Imaging \t\t\t" + boolean2txt(LiveCell));
	print(logSettings, "Channel 1 \t\t\t\t" + setChan1);
	print(logSettings, "Channel 2 \t\t\t\t" + setChan2);
	print(logSettings, "Channel 3 \t\t\t\t" + setChan3);
	print(logSettings, "Channel 4 (optional) \t\t\t" + setChan4);
	print(logSettings, "Circularity \t\t\t\t" + set_circularity);
	print(logSettings, "ROI detection based on \t\t\t" + roiDetect);
	print(logSettings, "If single channel detection, used \t" + setRoiChan);
	print(logSettings, "Segmentation Threshold \t\t\t" + setSegmentThr);
	print(logSettings, "Gaussian Blur Filter \t\t\t" + boolean2txt(set_gaussianFilter));
	print(logSettings, "Gaussian Sigma \t\t\t\t" + set_gaussianSigma);
	print(logSettings, "Histogram mode scaling \t\t\t" + boolean2txt(set_histoscale));
	print(logSettings, "Background Substraction \t\t" + boolean2txt(BGsubstract));
	print(logSettings, "BG substraction on channel \t\t" + setBGsubChan);
	print(logSettings, "Timestamp \t\t\t\t" + File.dateLastModified(resultDir + separator + file + "_RoiSet.zip"));

	File.close(logSettings);
}

function boolean2txt(pValue) {
	if (pValue == 0) {
		return "false"
	}
	else {
		return "true"
	}
}
