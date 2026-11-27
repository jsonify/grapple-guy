import Foundation

/// The order holes are played in: `App/Levels/courses.json` (see docs/levels.md).
/// A course is a run of holes (usually 9) played in order, like a round of golf (#30).
public struct Course: Equatable, Sendable, Decodable {
    public var name: String
    /// Level file names (without `.json`), in play order.
    public var holes: [String]

    public init(name: String, holes: [String]) {
        self.name = name
        self.holes = holes
    }
}

public enum CourseListError: Error, Equatable {
    case noCourses
    case emptyCourse(String)
    case duplicateHole(String)
}

public struct CourseList: Equatable, Sendable, Decodable {
    public var courses: [Course]

    public init(courses: [Course]) throws {
        guard !courses.isEmpty else { throw CourseListError.noCourses }
        var seen = Set<String>()
        for course in courses {
            guard !course.holes.isEmpty else { throw CourseListError.emptyCourse(course.name) }
            for hole in course.holes {
                guard seen.insert(hole).inserted else { throw CourseListError.duplicateHole(hole) }
            }
        }
        self.courses = courses
    }

    private enum CodingKeys: String, CodingKey { case courses }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(courses: c.decode([Course].self, forKey: .courses))
    }

    public static func decode(_ data: Data) throws -> CourseList {
        try JSONDecoder().decode(CourseList.self, from: data)
    }

    /// Every hole in play order, with where it sits in its course.
    public var allHoles: [HoleRef] {
        courses.enumerated().flatMap { courseIndex, course in
            course.holes.enumerated().map { holeIndex, file in
                HoleRef(file: file, course: course.name, courseIndex: courseIndex, number: holeIndex + 1)
            }
        }
    }
}

/// One hole's place in the course list.
public struct HoleRef: Equatable, Hashable, Sendable {
    /// Level file name (without `.json`).
    public var file: String
    public var course: String
    public var courseIndex: Int
    /// 1-based hole number within its course.
    public var number: Int

    public init(file: String, course: String, courseIndex: Int, number: Int) {
        self.file = file
        self.course = course
        self.courseIndex = courseIndex
        self.number = number
    }
}
