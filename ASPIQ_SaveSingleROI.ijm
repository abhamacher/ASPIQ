#@ String (visibility=MESSAGE, value="ASPIQ macro to save a single ROI as .zip file in an image specific directory.") topMsg
#@ File (label = "Save ROI to:", style = "directory") output

/* 	Last update: 	28th February 2020
 *	Script author: 	Anna Hamacher, HHU
 *  Workaround to save a single ROI into a .zip file (does not work in the GUI)
 *  Output name based on ASPIQ source directory
 */
 
separator = File.separator;
lastPathName = File.getName(output);
imageFile = substring(lastPathName, 0, lastIndexOf(lastPathName, "_results"));

roiManager("Deselect");
roiManager("Save", output + separator + imageFile + "_RoiSet.zip");

showMessage("Macro finished.");