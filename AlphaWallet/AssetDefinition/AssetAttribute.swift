// Copyright © 2018 Stormbird PTE. LTD.

import UIKit
import SwiftyXMLParser
import BigInt

protocol AssetAttributeValue {}
extension String: AssetAttributeValue {}
extension Int: AssetAttributeValue {}
extension GeneralisedTime: AssetAttributeValue {}

enum AssetAttributeSyntax: String {
    case directoryString = "1.3.6.1.4.1.1466.115.121.1.15"
    case generalisedTime = "1.3.6.1.4.1.1466.115.121.1.24"
    case iA5String = "1.3.6.1.4.1.1466.115.121.1.26"
    case integer = "1.3.6.1.4.1.1466.115.121.1.27"

    func extract(from string: String, isMapping: Bool) -> Any? {
        switch self {
        case .generalisedTime:
            return GeneralisedTime(string: string)
        case .directoryString, .iA5String:
            if isMapping {
                return string
            } else {
                guard let value = BigInt(string) else { return "" }
                return String(data: Data(bytes: String(value, radix: 16).hexa2Bytes), encoding: .utf8)
            }
        case .integer:
            return Int(string)
        }
    }
}

enum AssetAttribute {
    case mapping(attribute: XML.Accessor, syntax: AssetAttributeSyntax, lang: String, bitmask: BigInt, bitShift: Int)
    case direct(attribute: XML.Accessor, syntax: AssetAttributeSyntax, bitmask: BigInt, bitShift: Int)

    init(attribute: XML.Element, lang: String) {
        self = {
            let attributeAccessor = XML.Accessor(attribute)
            //TODO show error if syntax attribute is missing
            if case .singleElement(let origin) = attributeAccessor["origin"], let rawSyntax = attributeAccessor.attributes["syntax"], let syntax = AssetAttributeSyntax(rawValue: rawSyntax), let type = XML.Accessor(origin).attributes["as"], let bitmaskString = AssetAttribute.getBitMaskFrom(attribute: attributeAccessor), let bitmask = BigInt(bitmaskString, radix: 16) {
                let bitShift = AssetAttribute.bitShiftCount(forBitMask: bitmask)
                switch type {
                case "mapping":
                    return .mapping(attribute: attributeAccessor, syntax: syntax, lang: lang, bitmask: bitmask, bitShift: bitShift)
                default:
                    return .direct(attribute: attributeAccessor, syntax: syntax, bitmask: bitmask, bitShift: bitShift)
                }
            }
            //TODO maybe return an optional to indicate error instead?
            return .direct(attribute: attributeAccessor, syntax: .iA5String, bitmask: BigInt(0), bitShift: 0)
        }()
    }

    func extract<T>(from tokenValueHex: String) -> T? where T: AssetAttributeValue {
        switch self {
        case .mapping(let attribute, let syntax, let lang, _, _):
            guard let key = parseValue(tokenValueHex: tokenValueHex) else { return nil }
            guard let value = attribute["origin"]["option"].getElementWithKeyAttribute(equals: String(key))?["value"].getElementWithLangAttribute(equals: lang)?.text else { return nil }
            return syntax.extract(from: value, isMapping: true) as? T
        case .direct(_, let syntax, _, _):
            guard let value = parseValue(tokenValueHex: tokenValueHex) else { return nil }
            return syntax.extract(from: String(value), isMapping: false) as? T
        }
    }

    private func parseValue(tokenValueHex: String) -> BigInt? {
        switch self {
        case .direct(let attribute, _, let bitmask, let bitShift), .mapping(let attribute, _, _, let bitmask, let bitShift):
            guard let tokenHexAsInt = BigInt(tokenValueHex, radix: 16) else { return nil }
            return (bitmask & tokenHexAsInt) >> bitShift
        }
    }

    private static func getBitMaskFrom(attribute: XML.Accessor) -> String? {
        return attribute["origin"].attributes["bitmask"]
    }

    ///Used to truncate bits to the right of the bitmask
    private static func bitShiftCount(forBitMask bitmask: BigInt) -> Int {
        var count = 0
        repeat {
            count += 1
        } while bitmask % (1 << count) == 0
        return count - 1
    }
}
