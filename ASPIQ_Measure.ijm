#@ String (visibility=MESSAGE, value="Choose the images to be processed:") topMsg
#@ File (label = "Main directory", style = "directory") workingDir
#@ String (label = "File suffix", value = ".czi") suffix
#@ Boolean(label = "Live Cell Imaging", value = false) LiveCell
#@ String (visibility=MESSAGE, value="Choose threshold per channel:") thrMsg
#@ String(label = "C1", choices={"Otsu", "Triangle", "Default", "Li", "Moments", "Minimum", "Huang", "RenyiEntropy", "Yen", "IsoData", "Intermodes", "MaxEntropy"}, style="listBox") setThr1
#@ String(label = "C2", choices={"Otsu", "Triangle", "Default", "Li", "Moments", "Minimum", "Huang", "RenyiEntropy", "Yen", "IsoData", "Intermodes", "MaxEntropy"}, style="listBox") setThr2
#@ String(label = "C3", choices={"Otsu", "Triangle", "Default", "Li", "Moments", "Minimum", "Huang", "RenyiEntropy", "Yen", "IsoData", "Intermodes", "MaxEntropy"}, style="listBox") setThr3
#@ String(label = "(optional) C4", choices={"Otsu", "Triangle", "Default", "Li", "Moments", "Minimum", "Huang", "RenyiEntropy", "Yen", "IsoData", "Intermodes", "MaxEntropy"}, style="listBox") setThr4
#@ String(label = "Thresholding mode:", choices={"global", "local"}, style="radioButtonHorizontal") setThrMode
#@ String (visibility=MESSAGE, value="Note: global = on whole image; local = only on ROI area") thr2Msg
#@ String(label = "Thresholding on:", choices={"each channel", "single channel"}, style="radioButtonHorizontal") channelSelect
#@ String(label = "If single channel, use:", choices={"C1", "C2", "C3", "C4"}, style="listBox") setThrChan
#@ Boolean(label = "Slight Background Substraction", value = false) BGsubstract
#@ String(label = "If BG substraction, on channel:", choices={"C1", "C2", "C3", "C4", "all"}, style="listBox") setBGsubChan
#@ String (visibility=MESSAGE, value="Note: Background substraction removes information, use with caution!") bgs2Msg

/* 	Last update: 	28th February 2020
 *	Script author: 	Anna Hamacher, HHU
 *	Modification:	Laura Wörmeyer, HHU (normalisation to pancreatic nuclei area, #164-180)
 *	Modification:	Laura Wörmeyer, HHU (added line 64, sum slices for apotome images)
 *	
 *	Macro to process multiple images in a folder to 
 *	- measure specific thresholds inside this area for each channel
 *	- save the results in a directory for evaluation of the automation and reproducibility.
 *	So far, apotome images can cause problems, if the bio-format importer of Fiji fails to stitch the tiles. 
 */
 
scriptStart = round(getTime()/1000);

// General settings
separator = File.separator;
myThr = newArray(setThr1, setThr2, setThr3, setThr4);

// Main function
run("Clear Results");
processFolder(workingDir);

function processFolder(workingDir) {
	list = getFileList(workingDir);
	Array.sort(list); 
	for (i = 0; i < list.length; i++) {
		if(File.isDirectory(workingDir + separator + list[i])){
			processFolder("" + workingDir + separator + list[i]);
		} 
		else if(endsWith(list[i], suffix)){
			processFile(workingDir, list[i]);
		}
	}
}
	
function processFile(workingDir, file) {
	print("Processing: " + workingDir + separator + file);

	setBatchMode(true); 	
	run("Bio-Formats Importer", "open=[" + workingDir + separator + file + "] autoscale color_mode=Composite rois_import=[ROI manager] view=Hyperstack stack_order=XYCZT stitch_tiles series_1");
	imageTitle = getTitle(); // needed for more than 1 til (string incl. "#1")
	imageId = getImageID(); 
	totalSlices = nSlices();
	
	// Perform max intensity projection in case of live cell z-stack images
	if (LiveCell && totalSlices > 4) {
		run("Z Project...", "projection=[Max Intensity]");
		run("Z Project...", "projection=[Sum Slices]");
		Stack.setDisplayMode("composite");
		close(imageTitle);
		selectWindow("MAX_" + imageTitle);
		rename(imageTitle);
	}
	
	// Decision of measurement on each or only a single channel
	if (channelSelect == "each channel") {
		iGlobal = 1;
		totalSlices = nSlices();
	} else {
		iGlobal = substring(setThrChan, 1); 
		totalSlices = iGlobal;
	}
	// Change image to 8-bit
	run("8-bit");
	run("Split Channels");
	for (i=iGlobal; i <= totalSlices ; i++)  {
		selectWindow("C" + i + "-" + imageTitle);
		run("8-bit");

		// Perform a slight background substraction in case of very noisy stainings
		if (BGsubstract) {
			if (setBGsubChan == "all" || substring(setBGsubChan, 1) == i) {
				run("Subtract Background...", "rolling=150");
			}
		}
	}
	// Clear ROIs
	roiManager("reset");
	// Import predefined ROIs
	roiManager("Open", workingDir + file + "_RoiSet.zip");
	nROIs = roiManager("count");
	if (nROIs < 0) { 
		print (file + ": Invalid operation, no ROI defined!"); // Debug
		exit(); 
	}
	// Set measurement paramaters, don't limit to threshold
	run("Set Measurements...", "area area_fraction display redirect=None decimal=4");
	// First measure total area of each ROI
	for (j=0; j < nROIs; j++) {
		roiManager("Deselect");
		selectWindow("C" + iGlobal + "-" + imageTitle);
		roiManager("Select", j);
		run("Measure"); 
		roiManager("Deselect");
		}
	// Measurement of white area, limit to threshold now
	run("Set Measurements...", "area area_fraction limit display redirect=None decimal=4");
	// Measure the area of each ROI on each specific channel threshold
	if (setThrMode == "local") {
		// Perform local thresholding by selecting the ROIs before thresholding
		for (j=0; j < nROIs; j++) {
			for (i=iGlobal; i <= totalSlices ; i++)  {
				selectWindow("C" + i + "-" + imageTitle);
				run("Select All");
				// Convert image for thresholding and measure the relevant area
				// This needs to be done per channel and per ROI
				thrWindow = "C" + i + " with Threshold " + myThr[i-1] + "_roi" + j;
				run("Duplicate...", "title=[" + thrWindow + "]");
				selectWindow(thrWindow);
				roiManager("Select", j);
				roiName = Roi.getName();
				setAutoThreshold(myThr[i-1] + " dark");	
				setOption("BlackBackground", true);	
				run("Convert to Mask");
				roiManager("Deselect");
				selectWindow(thrWindow);
				roiManager("Select", j);
				run("Measure");
				// Save each mask with ROI
				run("Flatten");
				saveAs("Tiff", workingDir + file + "_C" + i + "_Threshold_" + myThr[i-1] + "_roi_" + roiName + ".tif");
			}
		}
	}
	else {
		// Perform global thresholding on whole image
		for (i=iGlobal; i <= totalSlices ; i++)  {
			selectWindow("C" + i + "-" + imageTitle);
			run("Select All");
			// Convert image for thresholding and measure the relevant area
			// This needs to be done per channel and per ROI
			thrWindow = "C" + i + " with Threshold " + myThr[i-1];
			run("Duplicate...", "title=[" + thrWindow + "]");
			selectWindow(thrWindow);
			setAutoThreshold(myThr[i-1] + " dark");	
			setOption("BlackBackground", true);					
			run("Convert to Mask");
			for (j=0; j < nROIs; j++) {
				roiManager("Deselect");
				selectWindow(thrWindow);
				roiManager("Select", j);
				run("Measure");
			}
			// Save each mask
			roiManager("Deselect");
			saveAs("Tiff", workingDir + file + "_C" + i + "_Threshold_" + myThr[i-1] + ".tif");
		}
	}
	/*
	// Normalisation to pancreatic nuclei area
	// Calculate overlap of C1 and C2, works only for global thresholding
	if (LiveCell) {
		if (setThrMode == "global") {
			imageCalculator("Add create", imageTitle + "_C1_Threshold_" + myThr[0] + ".tif", imageTitle + "_C2_Threshold_" + myThr[1] + ".tif");
			run("Convert to Mask");
			// selectWindow("Result of " + imageTitle + "_C1_Threshold_" + myThr[0] + ".tif");
			rename("Merged C1 and C2 of " + imageTitle + ".tif");
			for (j=0; j < nROIs; j++) {
				roiManager("Deselect");
				roiManager("Select", j);
				run("Measure");
			}
			roiManager("Deselect");
			saveAs("Tiff", workingDir + file + "_C1_add_C2" + ".tif");
		}
	} 
	*/
	run("Close All");
	setBatchMode(false);
}

// Save the results to an overall file
timestamp = round(getTime()/1000);
selectWindow("Results");
saveAs("Results", workingDir + separator + "Overall_Quantification_Results_" + timestamp + ".csv"); 

logSettings = File.open(workingDir + separator + "Overall_Quantification_Results_" + timestamp + "_settings.txt");

print(logSettings, "PARAMETER \t\t\t\t VALUE");
	print(logSettings, "===================================================================================================");
	print(logSettings, "Live Cell Imaging \t\t\t" + boolean2txt(LiveCell));
	print(logSettings, "Threshold channel 1 \t\t\t" + setThr1);
	print(logSettings, "Threshold channel 2 \t\t\t" + setThr2);
	print(logSettings, "Threshold channel 3 \t\t\t" + setThr3);
	print(logSettings, "(Optional) Threshold channel 4 \t\t" + setThr4);
	print(logSettings, "Thresholding mode \t\t\t" + setThrMode);
	print(logSettings, "Thresholding on \t\t\t" + channelSelect);
	print(logSettings, "If single channel, used \t\t" + setThrChan);
	print(logSettings, "Background Substraction \t\t" + boolean2txt(BGsubstract));
	print(logSettings, "BG substraction on channel \t\t" + setBGsubChan);
	print(logSettings, "Timestamp \t\t\t\t" + File.dateLastModified(workingDir + separator + "Overall_Quantification_Results_" + timestamp + ".csv"));

File.close(logSettings);

// Get the total runtime of the script in seconds and display to user
scriptEnd = round(getTime()/1000);
totalRuntime = scriptEnd - scriptStart;
showMessage("ASPIQ Measure Script ended, runtime: " + totalRuntime + "s");

function boolean2txt(pValue) {
	if (pValue == 0) {
		return "false"
	}
	else {
		return "true"
	}
}
