//
//  ArticleDB.swift
//
//  Created by Norbert Thies on 04.04.20.
//  Copyright © 2020 Norbert Thies. All rights reserved.
//

import Foundation
import CoreData
import NorthLib

/// A quite simple Database derivation
public class ArticleDB: Database {  
  
  /// There is only one article DB in the app
  public static var singleton: ArticleDB!
  
  /// Initialize with name of database, open it and call the passed closure
  @discardableResult
  public init(name: String, closure: @escaping (Error?)->()) { 
    super.init(name: name, model: "ArticleDB") 
    ArticleDB.singleton = self
    self.open { err in closure(err) }
  }    
  
  /// The managed object context
  public static var context: NSManagedObjectContext { return singleton.context! } 
  
  /// Save the singleton's context
  public static func save() { singleton.save() }
  
} // ArticleDB

/// A Protocol to extend CoreData objects
public protocol PersistentObject: NSManagedObject, DoesLog {}

public extension PersistentObject {
  /// The unique ID of every CoredData entity as String
  var id: String { objectID.uriRepresentation().absoluteString }
  /// Get object using its ID
  static func get(id: String) -> Self? { 
    let uri = URL(string: id)
    let coordinator = ArticleDB.singleton.coordinator
    if let uri = uri,
       let oid = coordinator.managedObjectID(forURIRepresentation: uri) {
      return ArticleDB.context.object(with: oid) as? Self
    }
    return nil
  }
  /// Delete the object from the persistent store
  func delete() { ArticleDB.context.delete(self) }
} // PersistentObject

/// A StoredObject is in essence a PersistentObject Wrapper
public protocol StoredObject: DoesLog {
  
  associatedtype PO: PersistentObject
  associatedtype Object
  var pr: PO { get }                      // persistent record
  var id: String { get }                  // ID of persistent record
  init(persistent: PO)                    // create stored record from persistent one
  /// Update from passed Object
  func update(from: Object)
  /// Get from passed Object
  static func get(object: Object) -> Self?
  static func persist(object: Object) -> Self
  static var entity: String { get }       // name of persistent entity
  static var fetchRequest: NSFetchRequest<PO> { get } // fetch request for persistent record
  
} // StoredObject

public extension StoredObject {  
  
  var id: String { pr.id } // ID of persistent record
  static var fetchRequest: NSFetchRequest<PO> { NSFetchRequest<PO>(entityName: entity) }

  /// Delete the object from the persistent store
  func deletePersistent() { pr.delete() }
  func delete() { deletePersistent() }

  /// Create a new persistent record
  static func newPersistent() -> PO {
    NSEntityDescription.insertNewObject(forEntityName: entity,
               into: ArticleDB.context) as! PO
  }
  
  /// Create a new stored and persistent record
  static func new() -> Self {
    Self(persistent: newPersistent())
  }
 
  /// Create new StoredObject and initialize from Object
  @discardableResult
  static func persist(object: Object) -> Self {
    var storedRecord: Self
    if let tmp = get(object: object) { storedRecord = tmp }
    else { storedRecord = new() }
    storedRecord.update(from: object)
    return storedRecord
  }
  
  /// Get record using its ID
  static func get(id: String) -> Self? { 
    if let rec = PO.get(id: id) { 
      return Self(persistent: rec) 
    }
    return nil
  }

  /// Execute fetch request and return persistent records
  static func getPersistent(request: NSFetchRequest<PO>) -> [PO] {
    do {
      let res = try ArticleDB.context.fetch(request)
      return res
    }
    catch let err { Log.error(err) }
    return []
  }

  /// Execute fetch request and return stored records
  static func get(request: NSFetchRequest<PO>) -> [Self] {
    return getPersistent(request: request).map { Self(persistent: $0) }
  }
  
  /// Return all stored records
  static func all() -> [Self] {
    let request = fetchRequest
    return get(request: request)
  }
  
  func save() { ArticleDB.save() }
  
} // StoredObject

extension PersistentFileEntry: PersistentObject {
  
  // Remove file if record is deleted and no other records point to this file
  public override func prepareForDeletion() {
    if let fn = name, let sd = subdir { 
      let path = "\(Database.appDir)/\(sd)/\(fn)"
      File(path).remove()
    }
  }
  
}

/// A stored FileEntry
public final class StoredFileEntry: FileEntry, StoredObject {
  
  public static var entity = "FileEntry"
  public var pr: PersistentFileEntry // persistent record
  public var name: String {
    get { pr.name! }
    set { pr.name = newValue }
  }
  /// Sub directory relative to Database.appDir where the file is stored
  public var subdir: String? { 
    get { pr.subdir }
    set { pr.subdir = newValue }
  }
  /// Absolute directory where the file is stored
  public var dir: String? {
    get {
      guard let sd = subdir else { return nil }
      return Database.appDir + "/" + sd
    }
    set (str) {
      guard let d = str else { return }
      subdir = String(d.dropFirst(Database.appDir.count + 1))
    }
  }
  /// Pathname of file (absolute path)
  public var path: String? {
    get {
      guard let d = dir else { return nil }
      return d + "/" + name
    }
    set {
      guard let fn = newValue else { return }
      let file = File(fn)
      dir = file.dirname
      name = file.basename
    }
  }
  public var storageType: FileStorageType {
    get { FileStorageType(pr.storageType!)! }
    set { pr.storageType = newValue.rawValue }
  }
  public var moTime: Date {
    get { pr.moTime! }
    set { pr.moTime = newValue }
  }
  public var size: Int64 {
    get { pr.size }
    set { pr.size = newValue }
  }
  public var storedSize: Int64 { 
    get { 
      if let p = path, pr.storedSize <= 0 { 
        let file = File(p)
        if file.exists { pr.storedSize = file.size }
      } 
      return pr.storedSize
    }
    set { pr.storedSize = newValue }
  }
  public var sha256: String {
    get { pr.sha256! }
    set { pr.sha256 = newValue }
  }
  public var payloads: [StoredPayload] { 
    var pls: [StoredPayload] = []
    for plpr in pr.payloads! { 
      pls += StoredPayload(persistent: plpr as! PersistentPayload) 
    }
    return pls
  }
  public var image: StoredImageEntry? {
    if let img = pr.image { return StoredImageEntry(persistent: img) }
    else { return nil }
  }
  
  public required init(persistent: PersistentFileEntry) { self.pr = persistent }
  
  /// Initialize from existing file
  public static func new(path: String, storageType: FileStorageType = .issue) -> Self? {
    var ret: Self? = nil
    let file = File(path)
    if file.exists {
      let fe = Self.new()
      fe.path = path
      fe.moTime = file.mTime
      fe.storageType = storageType
      fe.size = file.size
      fe.storedSize = fe.size
      fe.sha256 = file.sha256
      ret = fe
    }
    return ret
  }

  /// Overwrite the persistent values
  public func update(from: FileEntry) {
    pr.name = from.name
    pr.storageType = from.storageType.representation
    pr.moTime = from.moTime
    pr.size = from.size
    pr.sha256 = from.sha256      
  }
  
  /// Return stored record with given name  
  public static func get(name: String) -> [StoredFileEntry] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "name = %@", name)
    return get(request: request)
  }

  /// Return stored record with given SHA256  
  public static func get(sha256: String) -> [StoredFileEntry] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "sha256 = %@", sha256)
    return get(request: request)
  }
  
  /// Return stored record that matches the SHA256 of the passed object
  public static func get(object: FileEntry) -> StoredFileEntry? {
    let res = get(name: object.name)
    if res.count > 0 { return res[0] }
    else { return nil }
  }  
  
  /// Return all records of a payload
  public static func filesInPayload(payload: StoredPayload) -> [StoredFileEntry] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "%@ IN payloads", payload.pr)
    request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
    return get(request: request)
  }
  
  /// Return all animation files of a Moment
  public static func animationInMoment(moment: StoredMoment) -> [StoredFileEntry] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "momentAnimated = %@", moment.pr)
    return get(request: request)
  }
  
} // StoredFileEntry

extension PersistentImageEntry: PersistentObject {}

/// A stored ImageEntry
public final class StoredImageEntry: ImageEntry, StoredObject {
  
  public static var entity = "ImageEntry"
  public var pr: PersistentImageEntry // persistent record
  public var pf: PersistentFileEntry!
  public var name: String { pf.name! }
  public var path: String? { StoredFileEntry(persistent: pf).path }
  public var storageType: FileStorageType { FileStorageType(pf.storageType!)! }
  public var moTime: Date { pf.moTime! }
  public var size: Int64 { pf.size }
  public var sha256: String { pf.sha256! }
  public var resolution: ImageResolution { ImageResolution(pr.resolution!)! }
  public var type: ImageType { ImageType(pr.type!)! }
  public var alpha: Float? { pr.alpha }
  public var sharable: Bool { pr.sharable }
  public var author: StoredAuthor? { 
    if let au = pr.author { return StoredAuthor(persistent: au) }
    else { return nil }
  }
  public var moment: StoredMoment? { 
    (pr.moment != nil) ? StoredMoment(persistent: pr.moment!) : nil
  }
  
  public required init(persistent: PersistentImageEntry) { 
    self.pr = persistent 
    if let pf = persistent.file { self.pf = pf }
  }
  
  /// Initialize with image in existing file
  public static func new(path: String, resolution: ImageResolution = .normal,
              type: ImageType = .facsimile,
              storageType: FileStorageType = .issue) -> StoredImageEntry? {
    if let fe = StoredFileEntry.new(path: path, storageType: storageType) {
      let ie = StoredImageEntry.new()
      ie.pf = fe.pr
      ie.pr.file = ie.pf
      ie.pr.resolution = resolution.rawValue
      ie.pr.type = "facsimile"
      ie.pr.alpha = 1.0
      ie.pr.sharable = true
      return ie
    }
    return nil
  }

  /// Overwrite the persistent values
  public func update(from: ImageEntry) {
    var file: StoredFileEntry
    if pf == nil { file = StoredFileEntry.get(object: from) ?? StoredFileEntry.new() }
    else { file = StoredFileEntry(persistent: pf) }
    file.update(from: from)
    pf = file.pr
    pr.resolution = from.resolution.rawValue
    pr.type = from.type.rawValue
    pr.alpha = from.alpha ?? 1.0
    pr.sharable = from.sharable
    pr.file = pf
    pf.image = pr
  }
  
  /// Return stored record with given name  
  public static func get(name: String) -> [StoredImageEntry] {
    let files = StoredFileEntry.get(name: name)
    if files.count > 0 {
      if let img = files[0].image {
        return [img]
      }
      else {
        let sr = new()
        sr.pf = files[0].pr
        return [sr]
      }
    }
    return []
  }
  
  /// Return stored record with given SHA256  
  public static func get(sha256: String) -> [StoredImageEntry] {
    let files = StoredFileEntry.get(sha256: sha256)
    if files.count > 0 {
      if let img = files[0].image {
        return [img]
      }
    }
    return []
  }
  
  /// Return stored record that matches the name of the passed object
  public static func get(object: ImageEntry) -> StoredImageEntry? {
    let res = get(name: object.name)
    if res.count > 0 { return res[0] }
    else { return nil }
  }  
  
  /// Return all images of a Moment
  public static func imagesInMoment(moment: StoredMoment) -> [StoredImageEntry] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "moment = %@", moment.pr)
    request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
    return get(request: request)
  }
  
  /// Return all images of an Article
  public static func imagesInArticle(article: StoredArticle) -> [StoredImageEntry] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "%@ IN imageContent", article.pr)
    request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
    return get(request: request)
  }
  
  /// Return all images of a Section
  public static func imagesInSection(section: StoredSection) -> [StoredImageEntry] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "%@ IN imageContent", section.pr)
    request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
    return get(request: request)
  }
  
  /// Return all credited images of a Moment
  public static func creditedImagesInMoment(moment: StoredMoment) -> [StoredImageEntry] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "momentCredit = %@", moment.pr)
    request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
    return get(request: request)
  }
  
} // StoredImageEntry

extension PersistentMoment: PersistentObject {}

/// A stored Moment image
public final class StoredMoment: Moment, StoredObject {

  public static var entity = "Moment"
  public var pr: PersistentMoment // persistent record
  public var data: Data? {
    get { pr.data }
    set { pr.data = newValue }
  }
  public var image: UIImage? { (data == nil) ? nil : UIImage(data: data!) }
  public var images: [ImageEntry] { StoredImageEntry.imagesInMoment(moment: self) }
  public var creditedImages: [ImageEntry] 
    { StoredImageEntry.creditedImagesInMoment(moment: self) }
  public var animation: [FileEntry] { StoredFileEntry.animationInMoment(moment: self) }
  public var firstPage: StoredPage? {
    get {
      guard let pg = pr.firstPage else { return nil }
      return StoredPage(persistent: pg)
    }
    set {
      guard let spg = newValue else { return }
      pr.firstPage = spg.pr
      pr.firstPage?.moment = pr
    }
  }
  public var facsimile: ImageEntry? { firstPage?.facsimile }

  public required init(persistent: PersistentMoment) { 
    self.pr = persistent 
  }

  /// Overwrite the persistent values
  public func update(from: Moment) {
    if let new = from as? StoredMoment { data = new.data }
    // Add new images
    for img in from.images {
      let se = StoredImageEntry.persist(object: img)
      se.pr.moment = pr
      pr.addToImages(se.pr)
    }
    // Remove unneeded images
    for img in images as! [StoredImageEntry] {
      if !from.images.contains(where: { $0.name == img.name }) {
        pr.removeFromImages(img.pr)
      }
    }
    // Add new credited images
    for img in from.creditedImages {
      let se = StoredImageEntry.persist(object: img)
      se.pr.momentCredit = pr
      pr.addToCreditedImages(se.pr)
    }
    // Remove unneeded credited images
    for img in creditedImages as! [StoredImageEntry] {
      if !from.creditedImages.contains(where: { $0.name == img.name }) {
        pr.removeFromCreditedImages(img.pr)
      }
    }
    // Add new animation files
    for f in from.animation {
      let fe = StoredFileEntry.persist(object: f)
      fe.pr.momentAnimated = pr
      pr.addToAnimation(fe.pr)
    }
    // Remove unneeded animation files
    for file in animation as! [StoredFileEntry] {
      if !from.animation.contains(where: { $0.name == file.name }) {
        pr.removeFromAnimation(file.pr)
      }
    }
  } // update  
  
  /// Return stored record that matches the name of the passed object
  public static func get(object: Moment) -> StoredMoment? {
    let imgs = object.images
    if imgs.count > 0, let img = StoredImageEntry.get(object: imgs[0]) {
      return img.moment
    }
    else { return nil }
  }  
  
  /// Read Image data from file and store it in persistent record
  public func storeData(from file: String) {
    self.data = File(file).data
  }
  
} // Stored Moment

extension PersistentPayload: PersistentObject {}

/// A stored Payload
public final class StoredPayload: StoredObject, Payload {
  
  public static var entity = "Payload"  
  public var pr: PersistentPayload // persistent record
  public var bytesLoaded: Int64 {
    get { return pr.bytesLoaded }
    set { pr.bytesLoaded = newValue }
  }
  public var bytesTotal: Int64 {
    get { return pr.bytesTotal }
    set { pr.bytesTotal = newValue }
  }
  public var downloadStarted: Date? {
    get { return pr.downloadStarted }
    set { pr.downloadStarted = newValue }
  }
  public var downloadStopped: Date? {
    get { return pr.downloadStopped }
    set { pr.downloadStopped = newValue }
  }
  /// Relative path to destination directory
  public var subdir: String {
    get { return pr.localDir! }
    set { pr.localDir = newValue }
  }
  /// Absolute path to destination directory
  public var localDir: String {
    get { "\(Database.appDir)/\(subdir)" }
    set (ldir) {
      subdir = String(ldir.dropFirst(Database.appDir.count + 1))
    }
  }
  public var remoteBaseUrl: String {
    get { return pr.remoteBaseUrl! }
    set { pr.remoteBaseUrl = newValue }
  }
  public var remoteZipName: String? {
    get { return pr.remoteZipName }
    set { pr.remoteZipName = newValue }
  }
  public var issue: Issue? {
    if let pissue = pr.issue { return StoredIssue(persistent: pissue) }
    else { return nil }
  }
  public var resources: Resources? {
    if let pres = pr.resources { return StoredResources(persistent: pres) }
    else { return nil }
  }

  public lazy var storedFiles: [StoredFileEntry] = { 
    var fls: [StoredFileEntry] = []
    if let files = pr.files {
      for f in files {
        fls += StoredFileEntry(persistent: f as! PersistentFileEntry)
      }
    }
    return fls
  }()
  
  public var files: [FileEntry] { return storedFiles }
  
  public required init(persistent: PersistentPayload) { self.pr = persistent }
  
  public func reduceToOverview() {
    guard let issue = self.issue else { return }
    let toKeep = issue.overviewFiles
    for f in storedFiles {
      if !toKeep.contains(where: { k in k.name == f.name }) {
        f.pr.removeFromPayloads(self.pr)
        if f.payloads.count == 1 { f.delete() }
      }
    }
  }
  
  func delete() {
    // Delete file entries that don't belong to another payload
    for f in storedFiles {
      if f.payloads.count == 1 { f.delete() }
    }
    self.deletePersistent()
  }
  
  public func update(from: Payload) {
    var bytesTotal: Int64 = 0
    var bytesLoaded: Int64 = 0
    var order: Int64 = 0
    self.localDir = from.localDir
    for f in from.files {
      let fe = StoredFileEntry.persist(object: f)
      fe.pr.order = order
      fe.pr.addToPayloads(pr)
      fe.pr.subdir = subdir
      order += 1
      pr.addToFiles(fe.pr)
      bytesTotal += f.size
      bytesLoaded += fe.storedSize
    }
    // Delete unneeded files
    var toDelete: [StoredFileEntry] = []
    for file in files as! [StoredFileEntry] {
      if !from.files.contains(where: { $0.name == file.name }) {
        pr.removeFromFiles(file.pr)
        file.pr.removeFromPayloads(pr)
        toDelete += file
      }
    }
    for f in toDelete { 
      f.delete() 
    }
    self.bytesTotal = bytesTotal
    self.bytesLoaded = 0
    self.remoteBaseUrl = from.remoteBaseUrl
    self.remoteZipName = from.remoteZipName
  }
  
  public static func get(object: Payload) -> StoredPayload? { 
    if let issue = object.issue {
      return StoredIssue.get(object: issue)?.storedPayload
    }
    if let res = object.resources {
      return StoredResources.get(object: res)?.storedPayload
    }
    return nil
  }

} // StoredPayload

extension PersistentResources: PersistentObject {}


/// A stored list of resource files
public final class BundledResources : DoesLog {
  lazy var bundledFiles : [URL] = {
    return Bundle.main.urls(forResourcesWithExtension: "", subdirectory: "files")
  }() ?? []
  
//  lazy var bundledFilesDir : String? = {
//    return Bundle.main.resourceURL?.appendingPathComponent("files").absoluteString
//  }()...finally unused
  
  lazy var resourcesPayload : Result<[String:GqlResources],Error> = {
      guard let resourcesJsonFileUrl
              = Bundle.main.url(forResource: "resources",
                                withExtension: "json") else {
        return .failure(self.fatal("Bundled resources.json Not found"))
      }
      let bundledResources = File(resourcesJsonFileUrl)
      
      if bundledResources.exists == false {
        return .failure(self.fatal("Bundled resources.json File Not exist!"))
      }
      
      do {
        let dec = JSONDecoder()
        
//        self.debug("Try to decode: \"\(String(decoding: bundledResources.data, as: UTF8.self)[0..<2000])\"")
        
        let dict = try dec.decode([String:[String:GqlResources]].self,
                                  from: bundledResources.data)
        return .success(dict["data"]!)
      }
      catch let error {
        return .failure(self.fatal("JSON decoding error: \(error)"))
      }
  }()
}

/// A stored list of resource files
public final class StoredResources: Resources, StoredObject {
  
  public static var entity = "Resources"
  public var pr: PersistentResources // persistent record
  public var storedPayload: StoredPayload? {
    if let ppl = pr.payload { return StoredPayload(persistent: ppl) }
    else { return nil }
  }
  public var payload: Payload { storedPayload! }
  public var resourceBaseUrl: String { payload.remoteBaseUrl }
  public var resourceZipName: String { payload.remoteZipName! }
  public var resourceVersion: Int {
    get { return Int(pr.resourceVersion) }
    set { pr.resourceVersion = Int32(newValue) }
  }
  public var localDir: String { payload.localDir }
  public var resourceFiles: [FileEntry] { payload.files }
  public var isDownloading: Bool = false
  public var isComplete: Bool { 
    get { return payload.isComplete }
    set {}
  }

  public required init(persistent: PersistentResources) { self.pr = persistent }

  /// Return stored record with given resourceVersion  
  public static func get(version: Int) -> [StoredResources] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "resourceVersion = %d", version)
    return get(request: request)
  }
  
  /// Return stored record with latest (largest) resourceVersion
  public static func latest() -> StoredResources? {
    let request = fetchRequest
    request.fetchLimit = 1
    request.sortDescriptors = [
      NSSortDescriptor(key: "resourceVersion", ascending: false)
    ]
    let res = get(request: request)
    if res.count > 0 { return res[0] }
    else { return nil }
  }
  
  public func update(from: Resources) {
    pr.payload = StoredPayload.persist(object: from.payload).pr
    pr.payload?.resources = pr
    resourceVersion = from.resourceVersion
  }
  
  /// Return Resources matching the resource version of the passed object
  public static func get(object: Resources) -> StoredResources? {
    let tmp = get(version: object.resourceVersion)
    if tmp.count > 0 { return tmp[0] }
    else { return nil }
  }
  
} // StoredResources

extension PersistentAuthor: PersistentObject {}

/// A stored Author
public final class StoredAuthor: Author, StoredObject {
  
  public static var entity = "Author"
  public var pr: PersistentAuthor // persistent record
  public var name: String? { pr.name }
  public var photo: ImageEntry? { 
    if let p = pr.photo { return StoredImageEntry(persistent: p) }
    else { return nil }
  }
  
  public required init(persistent: PersistentAuthor) { self.pr = persistent }

  /// Overwrite the persistent values
  public func update(from object: Author) {
    pr.name = object.name
    if let photo = object.photo {
      let imageEntry = StoredImageEntry.persist(object: photo)
      pr.photo = imageEntry.pr
      imageEntry.pr.author = pr
    }
    else { pr.photo = nil }
  }
  
  /// Return stored record with given name  
  public static func get(name: String) -> [StoredAuthor] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "name = %@", name)
    return get(request: request)
  }
  
  /// Return stored record with given photo  
  public static func get(photo: ImageEntry) -> [StoredAuthor] {
    let imgs = StoredImageEntry.get(name: photo.name) 
    if imgs.count > 0 {
      if let au = imgs[0].author {
        return [au]
      }
    }
    return []
  }
    
  public static func get(object: Author) -> StoredAuthor? {
    var tmp: [StoredAuthor] = []
    if let name = object.name { tmp = get(name: name) }
    if tmp.count == 0, let photo = object.photo { tmp = get(photo: photo) }
    if tmp.count < 1 { return nil }
    else { return tmp[0] }
  }
  
  /// Return all Authors of an Article
  public static func authorsOfArticle(article: StoredArticle) -> [StoredAuthor] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "%@ IN articles", article.pr)
    return get(request: request)
  }
  
} // StoredAuthor

extension PersistentArticle: PersistentObject {}

/// A stored Article
public final class StoredArticle: Article, StoredObject {
  
  public static var entity = "Article"
  public var pr: PersistentArticle // persistent record
  public var text: String? {
    get { return pr.text }
    set { pr.text = newValue }
  }
  public var title: String? {
    get { return pr.title }
    set { pr.title = newValue }
  }
  public var html: FileEntry {
    get { return StoredFileEntry(persistent: pr.html!) }
    set { 
      pr.html = StoredFileEntry.persist(object: newValue).pr 
      pr.html!.content = pr
    }
  }
  public var audio: FileEntry? {
    get { 
      if let pau = pr.audio { return StoredFileEntry(persistent: pau) }
      else { return nil } 
    }
    set { 
      if let au = newValue { 
        pr.audio = StoredFileEntry.persist(object: au).pr
        pr.audio?.articleAudio = pr
      }
      else { pr.audio = nil }      
    }
  }
  public var lastArticlePosition: Int {
    get { return Int(pr.lastArticlePosition) }
    set { pr.lastArticlePosition = Int64(newValue) }
  }
  public var onlineLink: String? {
    get { return pr.onlineLink }
    set { pr.onlineLink = newValue }
  }
  public var teaser: String? {
    get { return pr.teaser }
    set { pr.teaser = newValue }
  }
  public var hasBookmark: Bool {
    get { pr.hasBookmark }
    set {
      let old = pr.hasBookmark
      pr.hasBookmark = newValue
      if old != newValue {
        Notification.send("BookmarkChanged", content: sections, sender: self)
      }
    }
  }
  public var images: [ImageEntry]? { StoredImageEntry.imagesInArticle(article: self) }
  public var authors: [Author]? { StoredAuthor.authorsOfArticle(article: self) }
  public var pageNames: [String]? { nil }
  public var sections: [StoredSection] {
    var ret: [StoredSection] = []
    if let sections = pr.sections {
      for s in sections { ret += StoredSection(persistent: s as! PersistentSection) }
    }
    return ret
  }
  
  public required init(persistent: PersistentArticle) { self.pr = persistent }

  /// Overwrite the persistent values
  public func update(from object: Article) {
    if let sobject = object as? StoredArticle {
      self.text = sobject.text
      self.lastArticlePosition = sobject.lastArticlePosition
      self.hasBookmark = object.hasBookmark
    }
    self.title = object.title
    self.html = object.html
    self.audio = object.audio
    self.onlineLink = object.onlineLink
    self.teaser = object.teaser
    if let imgs = object.images {
      var order: Int32 = 0
      for img in imgs {
        let imageEntry = StoredImageEntry.persist(object: img)
        imageEntry.pr.addToImageContent(pr)
        imageEntry.pr.order = order
        pr.addToImages(imageEntry.pr)
        order += 1
      }
      // Remove unneeded images
      for img in images as! [StoredImageEntry] {
        if !imgs.contains(where: { $0.name == img.name }) {
          pr.removeFromImages(img.pr)
        }
      }
    }
    else { pr.images = nil }
    if let aus = object.authors {
      for au in aus {
        let sau = StoredAuthor.persist(object: au)
        sau.pr.addToArticles(pr)
        pr.addToAuthors(sau.pr)
      }
      // Remove unneeded authors
      for au in authors as! [StoredAuthor] {
        if !aus.contains(where: { $0.name == au.name }) {
          pr.removeFromAuthors(au.pr)
        }
      }
    }
    else { pr.authors = nil }
  }
  
  /// Return stored record with given name  
  public static func get(file: String) -> [StoredArticle] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "html.name = %@", file)
    return get(request: request)
  }
    
  public static func get(object: Article) -> StoredArticle? {
    let tmp = get(file: object.html.name)
    if tmp.count > 0 { return tmp[0] }
    else { return nil }
  }
  
  /// Return all Articles in a Section
  public static func articlesInSection(section: StoredSection) -> [StoredArticle] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "%@ IN sections", section.pr)
    request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
    return get(request: request)
  }
  
  /// Return all Articles in an Issue
  public static func articlesInIssue(issue: StoredIssue) -> [StoredArticle] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "%@ IN issues", issue.pr)
    request.sortDescriptors = [
      NSSortDescriptor(key: "Section.order", ascending: true),
      NSSortDescriptor(key: "order", ascending: true)
    ]
    return get(request: request)
  }
  
  /// Return all bookmarked Articles
  public static func bookmarkedArticles() -> [StoredArticle] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "hasBookmark = true")
    request.sortDescriptors = [
      NSSortDescriptor(key: "order", ascending: true)
    ]
    return get(request: request)
  }

} // StoredArticle

extension PersistentFrame: PersistentObject {}

/// A stored Frame
public final class StoredFrame: Frame, StoredObject {
  
  @discardableResult
  public static func persist(object: Frame, relatedPage: StoredPage) -> StoredFrame {
    var storedRecord: StoredFrame
    if let tmp = get(object: object, relatedPage: relatedPage) { storedRecord = tmp }
    else { storedRecord = new() }
    storedRecord.update(from: object)
    return storedRecord
  }
  
  public static var entity = "Frame"
  public var pr: PersistentFrame // persistent record
  public var link: String? {
    get { return pr.link }
    set { pr.link = newValue }
  }
  public var x1: Float {
    get { return pr.x1 }
    set { pr.x1 = newValue }
  }
  public var x2: Float {
    get { return pr.x2 }
    set { pr.x2 = newValue }
  }
  public var y1: Float {
    get { return pr.y1 }
    set { pr.y1 = newValue }
  }
  public var y2: Float {
    get { return pr.y2 }
    set { pr.y2 = newValue }
  }
  
  public required init(persistent: PersistentFrame) { self.pr = persistent }

  public static func get(object: Frame) -> Self? {
    let epsilon: Float = 0.0001
    let request = fetchRequest
    let p1 = NSPredicate(format: "abs(x1 - %f) < %f", object.x1, epsilon)
    let p2 = NSPredicate(format: "abs(x2 - %f) < %f", object.x2, epsilon)
    let p3 = NSPredicate(format: "abs(y1 - %f) < %f", object.y1, epsilon)
    let p4 = NSPredicate(format: "abs(y2 - %f) < %f", object.y2, epsilon)
    request.predicate = NSCompoundPredicate(type: .and,
                                            subpredicates: [p1, p2, p3, p4])
    let res = get(request: request)
    if res.count > 0 { return res[0] }
    return nil
  }
  
  public static func get(object: Frame, relatedPage: StoredPage) -> StoredFrame? {
    let epsilon: Float = 0.0001
    let request = fetchRequest
    let p1 = NSPredicate(format: "abs(x1 - %f) < %f", object.x1, epsilon)
    let p2 = NSPredicate(format: "abs(x2 - %f) < %f", object.x2, epsilon)
    let p3 = NSPredicate(format: "abs(y1 - %f) < %f", object.y1, epsilon)
    let p4 = NSPredicate(format: "abs(y2 - %f) < %f", object.y2, epsilon)
    request.predicate = NSCompoundPredicate(type: .and,
                                            subpredicates: [p1, p2, p3, p4])
    let res = get(request: request)
    
    for sf in res {
      if relatedPage.pr == sf.pr.page { return sf}
    }

    return nil
  }
  
  /// Overwrite the persistent values
  public func update(from object: Frame) {
    self.link = object.link
    self.x1 = object.x1
    self.x2 = object.x2
    self.y1 = object.y1
    self.y2 = object.y2
  }
    
  /// Return all Frames in a Page
  public static func framesInPage(page: StoredPage) -> [StoredFrame] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "page = %@", page.pr)
    request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
    return get(request: request)
  }

} // StoredFrame

extension PersistentPage: PersistentObject {}

/// A stored Page
public final class StoredPage: Page, StoredObject {
  
  public static var entity = "Page"
  public var pr: PersistentPage // persistent record
  public var title: String? {
    get { return pr.title }
    set { pr.title = newValue }
  }
  public var pagina: String? {
    get { return pr.pagina }
    set { pr.pagina = newValue }
  }
  public var pdf: FileEntry? {
    ///Debug Crash nil while unwrapping optional!
    ///no solution: return StoredFileEntry.new() ...crash on next place
    get {
      guard let pdf = pr.pdf else { return nil }
      return StoredFileEntry(persistent: pdf) }
    set {
      if let old = pr.pdf, old.name != newValue?.name { old.delete() }
      guard let newValue = newValue else { return }
      let persistedRecord = StoredFileEntry.persist(object: newValue).pr
      pr.pdf = persistedRecord
      persistedRecord.page = pr
    }
  }
  public var facsimile: ImageEntry? {
    get {
      createFacsimile()
      guard let pf = pr.facsimile else { return nil }
      return StoredImageEntry(persistent: pf)
    }
    set {
      if let img = newValue {
        pr.facsimile = StoredImageEntry.persist(object: img).pr
        pr.facsimile!.page = pr
      }
      else { pr.facsimile = nil }
    }
  }
  public var type: PageType {
    get { return PageType(pr.type!)! }
    set { pr.type = newValue.representation }
  }
  public var frames: [Frame]? { StoredFrame.framesInPage(page: self) }
  
  public required init(persistent: PersistentPage) { self.pr = persistent }
  
  /// Create facsimile image (if not available)
  private func createFacsimileImage() -> Bool {
    if let pdfPath = StoredFileEntry(persistent: pr.pdf!).path {
      let jpgPath = File.prefname(pdfPath) + ".jpg"
      if File(pdfPath).exists {
        if !File(jpgPath).exists {
          let img = UIImage.pdf(File(pdfPath).data)
          img?.save(to: jpgPath)
          return true
        }
        else { return true }
      }
    }
    return false
  }
  
  /// Create facsimile image from pdf, if not already available
  private func createFacsimile() {
    if pr.facsimile == nil,
       createFacsimileImage(),
       let pdfPath = StoredFileEntry(persistent: pr.pdf!).path {
      let jpgPath = File.prefname(pdfPath) + ".jpg"
      if let sie = StoredImageEntry.new(path: jpgPath) {
        pr.facsimile = sie.pr
        pr.facsimile!.page = pr
      }
    }
  }

  /// Overwrite the persistent values
  public func update(from object: Page) {
    if !(object is GqlPage) {
      log("Not expecting: \(Swift.type(of:object)) on update Page", logLevel: .Fatal)
    }
    self.title = object.title
    self.pdf = object.pdf
    self.facsimile = object.facsimile
    self.type = object.type
    self.pagina = object.pagina
    self.pr.frames = nil
    var order: Int32 = 0
    if let frames = object.frames {
      if let oldFrames = frames as? [StoredFrame] {
        for f in oldFrames { f.delete() }
      }
      for frame in frames {
        let sf = StoredFrame.persist(object: frame, relatedPage: self)
        sf.pr.page = self.pr
        sf.pr.order = order
        order += 1
        self.pr.addToFrames(sf.pr)
        sf.pr.article = nil
        if let link = sf.link {
          let arts = StoredArticle.get(file: link)
          if arts.count > 0 {
            let art = arts[0]
            sf.pr.article = art.pr
            art.pr.addToFrames(sf.pr)
          }
        }
      }
    }
  }
  
  /// Return stored record with given name
  public static func get(file: String) -> [StoredPage] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "pdf.name = %@", file)
    return get(request: request)
  }
    
  public static func get(object: Page) -> StoredPage? {
    guard let pdfName = object.pdf?.name else { return nil }
    let tmp = get(file: pdfName)
    if tmp.count > 0 { return tmp[0] }
    else { return nil }
  }
  
  /// Return all Pages in an Issue
  public static func pagesInIssue(issue: StoredIssue) -> [StoredPage] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "issue = %@", issue.pr)
    request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
    return get(request: request)
  }
  
  /// Return first of an Issue
  public static func pageOne(issue: StoredIssue) -> StoredPage? {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "issue = %@", issue.pr)
    request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
    request.fetchLimit = 1
    let res = get(request: request)
    if res.count > 0 { return res[0] }
    else { return nil }
  }

} // StoredPage

extension PersistentSection: PersistentObject {}

/// A stored Section
public final class StoredSection: Section, StoredObject {
  
  public static var entity = "Section"
  public var pr: PersistentSection // persistent record
  public var text: String? {
    get { return pr.text }
    set { pr.text = newValue }
  }
  public var name: String {
    get { return pr.name! }
    set { pr.name = newValue }
  }
  public var extendedTitle: String? {
    get { return pr.extendedTitle }
    set { pr.extendedTitle = newValue }
  }
  public var type: SectionType {
    get { return SectionType(pr.type!)! }
    set { pr.type = newValue.representation }
  }
  public var html: FileEntry {
    get { return StoredFileEntry(persistent: pr.html!) }
    set {
      if let old = pr.html, old.name != newValue.name { old.delete() }
      pr.html = StoredFileEntry.persist(object: newValue).pr 
      pr.html!.content = pr
    }
  }
  public var navButton: ImageEntry? {
    get { 
      if let pbutton = pr.navButton { return StoredImageEntry(persistent: pbutton) }
      else { return nil } 
    }
    set { 
      if let button = newValue {
        if let old = navButton as? StoredImageEntry, old.name != button.name {
          old.delete()
        }
        pr.navButton = StoredImageEntry.persist(object: button).pr
        pr.navButton?.addToNavSection(pr)
      }
      else { pr.navButton = nil }      
    }
  }

  public var images: [ImageEntry]? { StoredImageEntry.imagesInSection(section: self) }
  public var authors: [Author]? { nil }
  public var articles: [Article]? { StoredArticle.articlesInSection(section: self) }
  
  public required init(persistent: PersistentSection) { self.pr = persistent }

  /// Overwrite the persistent values
  public func update(from object: Section) {
    if let sobject = object as? StoredSection {
      self.text = sobject.text
    }
    self.name = object.name
    self.extendedTitle = object.extendedTitle
    self.type = object.type
    self.html = object.html
    self.navButton = object.navButton
    if let imgs = object.images {
      var order: Int32 = 0
      for img in imgs {
        let imageEntry = StoredImageEntry.persist(object: img)
        imageEntry.pr.addToImageContent(pr)
        imageEntry.pr.order = order
        pr.addToImages(imageEntry.pr)
        order += 1
      }
      // Remove unneeded images
      for img in images as! [StoredImageEntry] {
        if !imgs.contains(where: { $0.name == img.name }) {
          pr.removeFromImages(img.pr)
        }
      }
    }
    else { pr.images = nil }
    if let arts = object.articles {
      var order: Int32 = 0
      for art in arts {
        let newArt = StoredArticle.persist(object: art)
        newArt.pr.addToSections(self.pr)
        newArt.pr.order = order
        pr.addToArticles(newArt.pr)
        order += 1
      }
      // Remove unneeded articles
      for art in articles as! [StoredArticle] {
        if !arts.contains(where: { $0.html.name == art.html.name }) {
          debug("deleting \(art)")
          art.delete()
        }
      }
    }
    else { pr.articles = nil }
  }
  
  /// Return stored record with given name  
  public static func get(file: String) -> [StoredSection] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "html.name = %@", file)
    return get(request: request)
  }
  
  public static func get(object: Section) -> StoredSection? {
    let tmp = get(file: object.html.name)
    if tmp.count > 0 { return tmp[0] }
    else { return nil }
  }
  
  /// Return all Sections in an Issue
  public static func sectionsInIssue(issue: StoredIssue) -> [StoredSection] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "issue = %@", issue.pr)
    request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
    return get(request: request)
  }

} // StoredSection

extension PersistentIssue: PersistentObject {}

/// A stored Issue
public final class StoredIssue: Issue, StoredObject {
  
  public static var entity = "Issue"
  public var pr: PersistentIssue // persistent record
  public var feed: Feed { 
    get { StoredFeed(persistent: pr.feed!) }
    set { 
      if let sfeed = StoredFeed.get(object: newValue) {
        pr.feed = sfeed.pr
        pr.feed?.addToIssues(self.pr)
      }
    }
  }
  public var date: Date {
    get { return pr.date! }
    set { pr.date = newValue }
  }
  public var moTime: Date {
    get { return pr.moTime! }
    set { pr.moTime = newValue }
  }
  public var isWeekend: Bool {
    get { return pr.isWeekend }
    set { pr.isWeekend = newValue }
  }
  public var moment: Moment { 
    get { StoredMoment(persistent: pr.moment!) }
    set { 
      pr.moment = StoredMoment.persist(object: newValue).pr
      pr.moment?.issue = self.pr
    }
  }
  public var key: String? {
    get { return pr.key }
    set { pr.key = newValue }
  }
  public var baseUrl: String {
    get { return pr.baseUrl! }
    set { pr.baseUrl = newValue }
  }
  public var status: IssueStatus {
    get { return IssueStatus(pr.status!)! }
    set { pr.status = newValue.representation }
  }
  public var minResourceVersion: Int {
    get { return Int(pr.minResourceVersion) }
    set { pr.minResourceVersion = Int32(newValue) }
  }
  public var zipName: String? {
    get { return pr.zipName }
    set { pr.zipName = newValue }
  }
  public var zipNamePdf: String? {
    get { return pr.zipNamePdf }
    set { pr.zipNamePdf = newValue }
  }
  public var fileList: [String]? { nil }
  public var fileListPdf: [String]? { nil }
  public var imprint: Article? {
    get {
      if let pim = pr.imprint { return StoredArticle(persistent: pim) }
      else { return nil }
    }
    set {
      if let sim = newValue {
        if let old = pr.imprint, old.html?.name != sim.html.name {
          old.delete()
        }
        pr.imprint = StoredArticle.persist(object: sim).pr
        pr.imprint?.issueImprint = self.pr
      }
      else { pr.imprint = nil }
    }
  } 
  public var lastArticle: Int? {
    get { return (pr.lastArticle < 0) ? nil : Int(pr.lastArticle) }
    set(val) { pr.lastArticle = Int32((val==nil) ? -1 : val!) }
  }
  public var lastSection: Int? {
    get { return (pr.lastSection < 0) ? nil : Int(pr.lastSection) }
    set(val) { pr.lastSection = Int32((val==nil) ? -1 : val!) }
  }
  public var lastPage: Int? {
    get { return (pr.lastPage < 0) ? nil : Int(pr.lastPage) }
    set(val) { pr.lastPage = Int32((val==nil) ? -1 : val!) }
  }
  public var isComplete: Bool {
    get { return pr.isComplete }
    set { 
      pr.isComplete = newValue 
      if newValue { pr.isOvwComplete = newValue }
    }    
  }
  public var isOvwComplete: Bool {
    get { return pr.isOvwComplete }
    set { pr.isOvwComplete = newValue }    
  }
  public var storedPayload: StoredPayload? {
    if let ppl = pr.payload { return StoredPayload(persistent: ppl) }
    else { return nil }
  }
  public var payload: Payload { storedPayload! }

  public var sections: [Section]? { StoredSection.sectionsInIssue(issue: self) }
  public var pages: [Page]? { StoredPage.pagesInIssue(issue: self) }
  public var isDownloading: Bool = false

  public required init(persistent: PersistentIssue) { self.pr = persistent }

  /// Overwrite the persistent values
  public func update(from object: Issue) {
    self.feed = object.feed
    self.date = object.date
    self.moTime = object.moTime
    self.isWeekend = object.isWeekend
    self.moment = object.moment
    self.key = object.key
    self.baseUrl = object.baseUrl
    self.minResourceVersion = object.minResourceVersion
    self.zipName = object.zipName
    self.zipNamePdf = object.zipNamePdf
    self.imprint = object.imprint
    self.status = object.status
    let oldSections = sections
    let oldPages = pages
    if let secs = object.sections {
      var order: Int32 = 0
      for section in secs {
        let ssection = StoredSection.persist(object: section)
        ssection.pr.issue = self.pr
        ssection.pr.order = order
        pr.addToSections(ssection.pr)
        order += 1
      }
    }
    if let pages = object.pages {
      var order: Int32 = 0
      for page in pages {
        let spage = StoredPage.persist(object: page)
        spage.pr.issue = self.pr
        spage.pr.order = order
        pr.addToPages(spage.pr)
        order += 1
      }
    }
    // Remove sections no longer needed
    if let osecs = oldSections as? [StoredSection] {
      if let secs = object.sections {
        for s in osecs {
          if !secs.contains(where: { $0.html.name == s.html.name }) {
            s.delete()
          }
        }
      }
      else {
        for s in osecs { s.delete() }
      }
    }
    // Remove pages no longer needed
    if let opgs = oldPages as? [StoredPage] {
      if let pages = object.pages {
        for p in opgs {
          if !pages.contains(where: { $0.pdf?.name == p.pdf?.name && $0.pdf != nil }) {
            p.delete()
          }
        }
      }
      else {
        for p in opgs { p.delete() }
      }
    }
    pr.payload = StoredPayload.persist(object: object.payload).pr
    pr.payload?.issue = pr
    if let p1 = StoredPage.pageOne(issue: self) {
      let mom = StoredMoment(persistent: pr.moment!)
      mom.firstPage = p1
    }
  }
    
  /// Return stored record with given name  
  public static func get(date: Date, inFeed feed: StoredFeed) -> [StoredIssue] {
    let nsdate = NSDate(timeIntervalSinceReferenceDate:
                        date.timeIntervalSinceReferenceDate)
    let request = fetchRequest
    request.predicate = NSPredicate(format: "(date = %@) AND (feed = %@)", 
                                    nsdate, feed.pr)
    return get(request: request)
  }
  
  public static func get(object: Issue, inFeed feed: StoredFeed) -> StoredIssue? {
    let issues = get(date: object.date, inFeed: feed)
    if issues.count > 0 { return issues[0] }
    else { return nil }
  }
  
  public static func get(object: Issue) -> StoredIssue? {
    if let sfeed = StoredFeed.get(object: object.feed) {
      return get(object: object, inFeed: sfeed)
    }
    else { return nil }
  }
  
  /// Return an array of Issues in a Feed
  public static func issuesInFeed(feed: StoredFeed, count: Int = -1, fromDate: Date? = nil) 
    -> [StoredIssue] {
    let request = fetchRequest
    if let fromDate = fromDate {
      let nsdate = NSDate(timeIntervalSinceReferenceDate: fromDate.timeIntervalSinceReferenceDate)
      request.predicate = NSPredicate(format: "feed = %@ AND date <= %@", feed.pr, nsdate)
    }
    else { request.predicate = NSPredicate(format: "feed = %@", feed.pr) }      
    request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
    if count > 0 { request.fetchLimit = count }
    return get(request: request)
  }
  
  /// Return an array of Issues ordered by load date, ie. the oldest (by
  /// load date) comes first
  public static func firstLoaded(feed: StoredFeed, count: Int = -1) -> [StoredIssue] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "feed = %@ AND isComplete = true", feed.pr)
    request.sortDescriptors = [NSSortDescriptor(key: "payload.downloadStarted",
                                                ascending: true)]
    if count > 0 { request.fetchLimit = count }
    return get(request: request)
  }
  
  /// Returns the latest (ie. most current) issue stored
  public static func latest(feed: StoredFeed) -> StoredIssue? {
    let issues = issuesInFeed(feed: feed, count: 1)
    if issues.count >= 1 { return issues[0] }
    return nil
  }
  
  /// Remove oldest Issues and keep the newest ones
  public static func reduceOldest(feed: StoredFeed, keep: Int) {
    let issues = firstLoaded(feed: feed)
    if issues.count > keep {
      var n = issues.count
      for issue in issues {
        if n <= keep { break }
        issue.reduceToOverview()
        n -= 1
      }
    }
  }
  
  /// Deletes data that is not needed for overview
  public func reduceToOverview() {
    // Remove files not needed for overview
    storedPayload?.reduceToOverview()
    // Remove sections and cascading all data referenced by them
    if let secs = sections {
      for section in secs as! [StoredSection] {
        section.delete()
      }
    }
    (imprint as? StoredArticle)?.delete()
    if isComplete {
      isComplete = false
      isOvwComplete = true
    }
    ArticleDB.save()
  }
  
} // StoredIssue

extension PersistentFeed: PersistentObject {}

/// A stored Feed
public final class StoredFeed: Feed, StoredObject {
  
  public static var entity = "Feed"
  public var pr: PersistentFeed // persistent record
  public var name: String {
    get { return pr.name! }
    set { pr.name = newValue }
  }
  public var cycle: PublicationCycle {
    get { return PublicationCycle(pr.cycle!)! }
    set { pr.cycle = newValue.representation }
  }
  public var type: FeedType {
    get { return FeedType(pr.type!)! }
    set { pr.type = newValue.representation }
  }
  public var momentRatio: Float {
    get { return pr.momentRatio }
    set { pr.momentRatio = newValue }
  }
  public var issueCnt: Int {
    get { return Int(pr.issueCnt) }
    set { pr.issueCnt = Int64(newValue) }
  }
  public var firstIssue: Date {
    get { return pr.firstIssue! }
    set { pr.firstIssue = newValue }
  }
  public var lastIssue: Date {
    get { return pr.lastIssue! }
    set { pr.lastIssue = newValue }
  }
  public var lastIssueRead: Date? {
    get { return pr.lastIssueRead }
    set { pr.lastIssueRead = newValue }
  }
  public var lastUpdated: Date? {
    get { return pr.lastUpdated }
    set { pr.lastUpdated = newValue }
  }
  public var feeder: Feeder {
    get { return StoredFeeder(persistent: pr.feeder!) }
    set { 
      if let sfeeder = StoredFeeder.get(object: newValue) {
        pr.feeder = sfeeder.pr
        pr.feeder?.addToFeeds(self.pr)
      }
    }
  }

  public var storedIssues: [StoredIssue] { StoredIssue.issuesInFeed(feed: self) }
  public var issues: [Issue]? { storedIssues }
  
  public required init(persistent: PersistentFeed) { self.pr = persistent }

  /// Overwrite the persistent values
  public func update(from object: Feed) {
    self.name = object.name
    self.feeder = object.feeder
    self.feeder = object.feeder
    self.cycle = object.cycle
    self.type = object.type
    self.issueCnt = object.issueCnt
    self.momentRatio = object.momentRatio
    self.firstIssue = object.firstIssue
    self.lastIssue = object.lastIssue
    self.lastIssueRead = object.lastIssueRead
    self.lastUpdated = object.lastUpdated
    if let iss = object.issues {
      for issue in iss {
        let sissue = StoredIssue.persist(object: issue)
        sissue.pr.feed = pr
        pr.addToIssues(sissue.pr)
      }
      // Remove Issues no longer needed
      for issue in self.issues as! [StoredIssue] {
        if !iss.contains(where: { $0.date == issue.date }) {
          pr.removeFromIssues(issue.pr)
        }
      }
    }
  }
  
  /// Return stored Issue with given name in Feeder
  public static func get(name: String, inFeeder feeder: StoredFeeder) -> [StoredFeed] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "(name = %@) AND (feeder = %@)", 
                                    name, feeder.pr)
    return get(request: request)
  }
  
  public static func get(object: Feed, inFeeder feeder: StoredFeeder) -> StoredFeed? {
    let feeds = get(name: object.name, inFeeder: feeder)
    if feeds.count > 0 { return feeds[0] }
    else { return nil }
  }
  
  public static func get(object: Feed) -> StoredFeed? {
    if let sfeeder = StoredFeeder.get(object: object.feeder) {
      return get(object: object, inFeeder: sfeeder)
    }
    else { return nil }
  }
      
  /// Return all Feeds of a Feeder
  public static func feedsOfFeeder(feeder: StoredFeeder) -> [StoredFeed] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "feeder = %@", feeder.pr)
    return get(request: request)
  }

} // StoredFeed

extension PersistentFeeder: PersistentObject {}

/// A stored Feeder
public final class StoredFeeder: Feeder, StoredObject {

  public static var entity = "Feeder"
  public var pr: PersistentFeeder // persistent record
  public var title: String {
    get { return pr.title! }
    set { pr.title = newValue }
  }
  public var timeZone: String {
    get { return pr.timeZone! }
    set { pr.timeZone = newValue }
  }
  public var baseUrl: String {
    get { return pr.baseUrl! }
    set { pr.baseUrl = newValue }
  }
  public var globalBaseUrl: String {
    get { return pr.globalBaseUrl! }
    set { pr.globalBaseUrl = newValue }
  }
  public var resourceBaseUrl: String {
    get { return pr.resourceBaseUrl! }
    set { pr.resourceBaseUrl = newValue }
  }
  public var authToken: String? {
    get { return pr.authToken }
    set { pr.authToken = newValue }
  }
  public var lastUpdated: Date? {
    get { return pr.lastUpdated }
    set { pr.lastUpdated = newValue }
  }
  public var resourceVersion: Int {
    get { return Int(pr.resourceVersion) }
    set { pr.resourceVersion = Int32(newValue) }
  }
  public var storedResources: StoredResources? { 
    let res = StoredResources.get(version: resourceVersion) 
    if res.count > 0 { return res[0] }
    else { return nil }
  }
  public var resourceFiles: [StoredFileEntry] 
    { storedResources?.storedPayload?.storedFiles ?? [] }
  public var storedFeeds: [StoredFeed] { StoredFeed.feedsOfFeeder(feeder: self) }
  public var feeds: [Feed] { storedFeeds }
  
  public required init(persistent: PersistentFeeder) { self.pr = persistent }

  /// Overwrite the persistent values
  public func update(from object: Feeder) {
    self.title = object.title
    self.timeZone = object.timeZone
    self.baseUrl = object.baseUrl
    self.globalBaseUrl = object.globalBaseUrl
    self.resourceBaseUrl = object.resourceBaseUrl
    self.authToken = object.authToken
    self.resourceVersion = object.resourceVersion
    self.lastUpdated = object.lastUpdated
    for feed in object.feeds {
      let sfeed = StoredFeed.persist(object: feed)
      sfeed.pr.feeder = pr
      pr.addToFeeds(sfeed.pr)
    }
    // Do not remove Feeds no longer on server
  }
  
  /// Return stored record with given name/title 
  public static func get(name: String) -> [StoredFeeder] {
    let request = fetchRequest
    request.predicate = NSPredicate(format: "title = %@", name)
    return get(request: request)
  }
  
  public static func get(object: Feeder) -> StoredFeeder? {
    let feeders = get(name: object.title)
    if feeders.count > 0 { return feeders[0] }
    else { return nil }
  }
  
  public required init(title: String, url: String, closure:
    @escaping(Result<Feeder,Error>)->()) {
    let request = StoredFeeder.fetchRequest
    request.predicate = NSPredicate(format: "title = %@", title)
    let pfeeders = StoredFeeder.getPersistent(request: request)
    if pfeeders.count > 0 {
      self.pr = pfeeders[0]
      closure(.success(self))
    }
    else {
      pr = PersistentFeeder()
      closure(.failure(Log.error("No Feeder with name '\(title)' found"))) 
    }
  }

  public func authenticate(account: String, password: String, closure: 
    @escaping (Result<String, Error>) -> ()) {
    closure(.failure(error("Can't authenticate at DB Feeder")))
  }
  
  public func resources(closure: @escaping(Result<Resources,Error>)->()) {
    closure(.failure(error("Currently no resources available")))
  }
  
} // StoredFeeder
