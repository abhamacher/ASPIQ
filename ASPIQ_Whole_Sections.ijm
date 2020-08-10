#@ String (visibility=MESSAGE, value="Choose the images to be processed:") topMsg
#@ File (label = "Main directory", style = "directory") workingDir
#@ File (label = "Output directory", style = "directory") outputDir
#@ String (label = "File suffix", value = ".czi") suffix
#@ String (visibility=MESSAGE, value="Select the channel and threshold:") thrMsg
#@ String(label = "Channel", choices={"1", "2", "3", "4"}, style="listBox") setChanNum
#@ String(label = "Threshold", choices={"Otsu", "Triangle", "Default", "Li", "Moments", "Minimum", "Huang", "RenyiEntropy", "Yen", "IsoData", "Intermodes", "MaxEntropy"}, style="listBox") setThr

/* 	Last update: 	24th July 2019 
 *	Script author: 	Anna Hamacher, HHU
 *	
 *	Macro to process multiple whole section images in a folder to 
 *	- measure the threshold of one channel (e.g. DAPI)
 *	- save the results in a single csv-file.
 */

scriptStart = round(getTime()/1000);

// General settings
separator = File.separator;
myThr = setThr + " dark";

// Main function
run("Clear Results");
processFolder(workingDir);

function processFolder(workingDir) {
	list = getFileList(workingDir);
	for (i = 0; i < list.length; i++) {
		if(File.isDirectory(workingDir + separator + list[i])) 
			processFolder("" + workingDir + separator + list[i]);
		if(endsWith(list[i], suffix))
			processFile(workingDir, list[i]);
	}
}
	
function processFile(workingDir, file) {
	print("Processing: " + workingDir + separator + file);
	
	setBatchMode(true); 
	run("Bio-Formats Importer", "open=[" + workingDir + separator + file + "] autoscale color_mode=Composite rois_import=[ROI manager] view=Hyperstack stack_order=XYCZT stitch_tiles series_1");
	imageTitle = getTitle();
	
	// Clear ROIs and change image to 8-bit
	roiManager("reset");
	run("8-bit");	
	selectWindow(imageTitle);
	setSlice(setChanNum);
	run("Duplicate...", "title=[Threshold C" + setChanNum + " of " + file + "]");
	run("8-bit");
	// Global Thresholding 
	setAutoThreshold(myThr);
	setOption("BlackBackground", true);
	run("Convert to Mask");
	// Measurement of white area, limit to threshold
	run("Set Measurements...", "area area_fraction limit display redirect=None decimal=4");
	run("Measure");
	// Save threshold masks
	saveAs("Tiff", outputDir + separator + file + "_" + setThr + "_C" + setChanNum + ".tif");
	run("Close All");
	setBatchMode(false);
}

// Save the results to an overall file
timestamp = round(getTime()/1000);
selectWindow("Results");
saveAs("Results", outputDir + separator + "Overall_WS_Results_" + timestamp + ".csv"); 
// Get the total runtime of the script in seconds and display to user
scriptEnd = round(getTime()/1000);
totalRuntime = scriptEnd - scriptStart;
showMessage("ASPIQ Whole Sections Script ended, runtime: " + totalRuntime + "s");

