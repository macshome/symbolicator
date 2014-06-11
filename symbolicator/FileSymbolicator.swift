/*

Created by Tomaz Kragelj on 10.06.2014.
Copyright (c) 2014 Gentle Bytes. All rights reserved.

*/

import Foundation

class FileSymbolicator {
	func symbolicate(contents: String, archiveHandler: ArchiveHandler) -> String? {
		let optionalInformation = self.extractProcessInformation(contents)
		if !optionalInformation {
			return nil
		}
		
		// Unwrap information tuple from optional value.
		let information = optionalInformation!
		
		// Get starting address.
		let optionalStartAddress = self.matchBaseAddressForSymbolication(contents, identifier: information.identifier, version: information.version, build: information.build)
		if !optionalStartAddress {
			return nil
		}

		// Get the corresponding dwarf file.
		let optionalDwarfPath = archiveHandler.dwarfPathWithIdentifier(information.identifier, version: information.version, build: information.build)
		if !optionalDwarfPath {
			println("ERROR: No archive found!")
			return nil
		}
		
		// Find all matches in the crash log, using both, application name and identifier. Group 1 contains address, group 2 text to be replaced with symbolized location.
		var matches = RxMatch[]()
		matches += self.matchSymbolsForSymbolication(contents, identifier: information.name)
		matches += self.matchSymbolsForSymbolication(contents, identifier: information.identifier)
		println("Matched \(matches.count) addresses for symbolizing")
		
		// Extract array of addresses that need symbolication and symbolize them.
		let addresses = matches.map { $0.groups[1].value } as String[]
		let symbols = self.symbolicateAddresses(optionalStartAddress!, dwarfPath: optionalDwarfPath!, addresses: addresses)
		let symbolizedString = self.generateSymbolicatedString(contents, matches: matches, symbols: symbols)
		return symbolizedString
	}
	
	/* private */ func generateSymbolicatedString(contents: String, matches: RxMatch[], symbols: String[]) -> String {
		var previousIndex = 0
		var rawContents = contents.bridgeToObjectiveC()
		var symbolizedContents = String()
		
		// Iterate over all parts that need symbolication.
		for (index, match) in enumerate(matches) {
			let symbol = symbols[index]
			let replaceRange = match.groups[2].range!
			
			// Get the substring between previous match and current one.
			let skippedRange = NSRange(location: previousIndex, length: replaceRange.location - previousIndex)
			let skippedContents = rawContents.substringWithRange(skippedRange)
			
			// Append skipped substring and symbol.
			symbolizedContents += skippedContents
			symbolizedContents += symbol
			
			previousIndex = replaceRange.location + replaceRange.length
		}
		
		// Symbolicate remaining string.
		if previousIndex < countElements(contents) {
			symbolizedContents += rawContents.substringFromIndex(previousIndex)
		}
		
		return symbolizedContents
	}
	
	/* private */ func symbolicateAddresses(baseAddress: String, dwarfPath: String, addresses: String[]) -> String[] {
		let stdOutPipe = NSPipe()
		let stdErrPipe = NSPipe()
		let task = NSTask()
		task.launchPath = "/usr/bin/xcrun"
		task.arguments = ["atos", "-arch", "x86_64", "-o", dwarfPath, "-l", baseAddress] + addresses
		task.standardOutput = stdOutPipe
		task.standardError = stdErrPipe
		task.launch()
		task.waitUntilExit()
		
		let translatedData = stdOutPipe.fileHandleForReading.readDataToEndOfFile()
		let translatedString = NSString(data: translatedData, encoding: NSASCIIStringEncoding)
		return translatedString.componentsSeparatedByString("\n") as String[]
	}
	
	/* private */ func matchSymbolsForSymbolication(contents: NSString, identifier: String) -> RxMatch[] {
		let pattern: NSString = "^[0-9]+\\s+\(identifier)\\s+(0x[0-9a-fA-F]+)\\s+(.+)$"
		let regex = pattern.toRxWithOptions(NSRegularExpressionOptions.AnchorsMatchLines)
		return contents.matchesWithDetails(regex) as RxMatch[]
	}
	
	/* private */ func matchBaseAddressForSymbolication(contents: String, identifier: String, version: String, build: String) -> String? {
		let pattern: NSString = "^\\s+(0x[0-9a-fA-F]+)\\s+-\\s+(0x[0-9a-fA-F]+)\\s+[+]?\(identifier)\\s+\\(\(version)\\s*-\\s*\(build)\\)"
		let optionalMatch = pattern.toRxWithOptions(NSRegularExpressionOptions.AnchorsMatchLines)!.firstMatchWithDetails(contents)
		if !optionalMatch {
			println("ERROR: Didn't find starting address for \(identifier)")
			return nil
		}
		
		let result = optionalMatch!.groups[1].value
		println("Starting address is \(result)")
		return result
	}
	
	/* private */ func extractProcessInformation(contents: String) -> (name: String, identifier: String, version: String, build: String)? {
		let optionalProcessMatch = "^Process:\\s+([^\\[]+) \\[[^\\]]+\\]".toRxWithOptions(NSRegularExpressionOptions.AnchorsMatchLines)!.firstMatchWithDetails(contents)
		if !optionalProcessMatch {
			println("ERROR: Process name is missing!")
			return nil
		}
		
		let optionalIdentifierMatch = "^Identifier:\\s+(.+)$".toRxWithOptions(NSRegularExpressionOptions.AnchorsMatchLines)!.firstMatchWithDetails(contents)
		if !optionalIdentifierMatch {
			println("ERROR: Process identifier is missing!")
			return nil
		}
		
		let optionalVersionMatch = "^Version:\\s+([^ ]+) \\(([^)]+)\\)".toRxWithOptions(NSRegularExpressionOptions.AnchorsMatchLines)!.firstMatchWithDetails(contents)
		if !optionalVersionMatch {
			println("ERROR: Process version and build number is missing!")
			return nil
		}
		
		let name = optionalProcessMatch!.groups[1].value
		let identifier = optionalIdentifierMatch!.groups[1].value
		let version = optionalVersionMatch!.groups[1].value
		let build = optionalVersionMatch!.groups[2].value
		
		println("Detected \(identifier) [\(name) \(version) (\(build))]")
		return (name, identifier, version, build)
	}
}
