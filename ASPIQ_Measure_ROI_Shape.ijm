#@ String (visibility=MESSAGE, value="Choose the images to be processed:") topMsg
#@ File (label = "Main directory", style = "directory") workingDir
#@ String (label = "File suffix", value = ".czi") suffix
#@ Boolean(label = "Live Cell Imaging", value = false) LiveCell

/* 	Last update: 	18th February 2020 
 *	Script author: 	Anna Hamacher, HHU
 *	
 *	Macro to process multiple images in a folder to 
 *	- measure specific parameters for predefined ROIs.
 *	- save the results in one common csv-file.
 */
 
scriptStart = round(getTime()/1000);

// General settings
separator = File.separator;

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
	// the series_1 parameter is needed for images with more than one tile, otherwise probably ignored

	imageTitle = getTitle(); // needed in case of more than 1 tile (additional string incl. the "#1")
	imageId = getImageID(); 
	
	if (LiveCell) {
		run("Z Project...", "projection=[Max Intensity]");
		Stack.setDisplayMode("composite");
	}
	
	selectWindow(imageTitle);

	// Delete all ROIs on the list
	roiManager("reset");
	// Import predefined ROIs
	roiManager("Open", workingDir + file + "_RoiSet.zip");
	nROIs = roiManager("count");
	if (nROIs < 0) { 
		print (file + ": Invalid operation, no ROI defined!"); // debug
		exit(); 
	}

	// Define your relevant measurements below
	run("Set Measurements...", "area area_fraction shape perimeter feret's display redirect=None decimal=4");
	
	for (j=0; j < nROIs; j++) {
		roiManager("Deselect");
		selectWindow(imageTitle);
		roiManager("Select", j);
		run("Measure"); 
		roiManager("Deselect");
		}
	run("Close All");
	setBatchMode(false);
}

// Save the results to an overall file
timestamp = round(getTime()/1000);
selectWindow("Results");
run("Summarize");
saveAs("Results", workingDir + separator + "Shape_Quantification_" + timestamp + ".csv"); 

// get the total runtime of the script in seconds and display to user
scriptEnd = round(getTime()/1000);
totalRuntime = scriptEnd - scriptStart;
showMessage("ASPIQ Measure Script ended, runtime: " + totalRuntime + "s");

