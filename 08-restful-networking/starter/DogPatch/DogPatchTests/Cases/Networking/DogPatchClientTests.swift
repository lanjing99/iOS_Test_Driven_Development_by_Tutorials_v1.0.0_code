/// Copyright (c) 2019 Razeware LLC
/// 
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
/// 
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
/// 
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
/// 
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit
import XCTest
@testable import DogPatch

class MockURLSessionTask: URLSessionDataTask{
    var completionHandler: (Data?, URLResponse?, Error?) -> Void
    var url: URL
    var calledResume: Bool = false
    
    init(url: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void, queue: DispatchQueue? = nil) {
        self.url = url
        if let queue = queue {
            self.completionHandler = { data, response, error in
                queue.async {
                    completionHandler(data, response, error)
                }
            }
        }else{
            self.completionHandler = completionHandler
        }
    }
    
    override func resume() {
        calledResume = true
    }
}

class MockURLSession: URLSession{
    var queue: DispatchQueue!
    fileprivate func givenDispatchQueue(){
        queue = DispatchQueue.init(label: "com.DogPatchTests.MockSession")
    }
    
    override func dataTask(with url: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        return MockURLSessionTask.init(url: url, completionHandler: completionHandler, queue: queue)
    }
}

class DogPatchClientTests: XCTestCase {
    var sut: DogPatchClient!
    var baseURL: URL!
    var mockSession: MockURLSession!
    
    //MARK: helper methods
    fileprivate func getDogsURL() -> URL{
        return URL.init(string: "dogs", relativeTo: baseURL)!
    }
    
    fileprivate func whenGetDogs(data: Data? = nil, statusCode: Int = 200, error: Error? = nil)
        -> (calledCompletion: Bool, dogs:[Dog]?, error: Error?){
            let response = HTTPURLResponse.init(url: getDogsURL(), statusCode: statusCode, httpVersion: nil, headerFields: nil)
            var callCompletion = false
            var receivedDogs: [Dog]? = nil
            var receivedError: Error? = nil
            
            let mockTask = sut.gotDogs { (dogs, error) in
                callCompletion = true
                receivedDogs = dogs
                receivedError = error
                } as! MockURLSessionTask
            
            mockTask.completionHandler(data, response, error)
            return (callCompletion, receivedDogs, receivedError)
    }
    
    //MARK: overide methods
    override func setUp() {
        super.setUp()
        baseURL =  URL(string: "https://example.com/api/v2/")!
        mockSession = MockURLSession.init()
        sut = DogPatchClient(baseURL: baseURL, session: mockSession, responseQueue: nil)
    }
    
    override func tearDown() {
        baseURL = nil
        mockSession = nil
        sut = nil
        super.tearDown()
    }
    
  
    //MARK: test methods
    func test_init_sets(){
        XCTAssertEqual(baseURL, sut.baseURL)
        XCTAssertEqual(mockSession, sut.session)
//        XCTAssertEqual(DispatchQueue.main, sut.responseQueue);

    }
    
    func test_getDogs_callExpectedURL(){
        let getDogsURL = URL.init(string: "dogs", relativeTo: baseURL)
        let mockTask = sut.gotDogs { (_, _) in
            
        } as! MockURLSessionTask
        XCTAssertEqual(getDogsURL, mockTask.url)
    }
    
    func test_getDogs_callResumeOnTask(){
        let mockTask = sut.gotDogs { (_, _) in
            
            } as! MockURLSessionTask
        XCTAssertTrue(mockTask.calledResume)
    }
    
    func test_getDogs_givenResponseStatusCode500_callsCompletion(){
        let result = whenGetDogs(data: nil, statusCode: 500, error: nil)
        XCTAssertTrue(result.calledCompletion)
        XCTAssertNil(result.dogs)
        XCTAssertNil(result.error)
    }
    
    func test_getDogs_givenError_callsCompletionWithError() throws{
        let expectedError = NSError(domain: "com.DogPatchTest", code: 42, userInfo: nil)
        let result = whenGetDogs(data: nil, statusCode: 200, error: expectedError)
        XCTAssertTrue(result.calledCompletion)
        XCTAssertNil(result.dogs)
        let actualError = try XCTUnwrap(result.error as NSError?)
        XCTAssertEqual(actualError, expectedError)
    }
    
    func test_getDogs_givenValidJSON_callCompletionWithDogs() throws{
        let data = try Data.fromJSON(fileName: "GET_Dogs_Response")
        let decoder = JSONDecoder()
        let dogs = try decoder.decode([Dog].self, from: data)
        
        let result = whenGetDogs(data: data, statusCode: 200, error: nil)
        XCTAssertTrue(result.calledCompletion)
        XCTAssertEqual(result.dogs, dogs)
        XCTAssertNil(result.error)
    }
    
    func test_getDogs_giveInvalidJSON_callCompletionWithError() throws{
        let data = try Data.fromJSON(fileName: "GET_Dogs_MissingValuesResponse")
        var expectedError: NSError!
        
        do{
            _ = try JSONDecoder().decode([Dog].self, from: data)
        }catch{
            expectedError = error as NSError
        }
        
        let result = whenGetDogs(data: data, statusCode: 200, error: nil)
        let actualError = try XCTUnwrap(result.error as NSError?)
        XCTAssertTrue(result.calledCompletion)
        XCTAssertNil(result.dogs)
        XCTAssertEqual(actualError.domain, expectedError.domain)
        XCTAssertEqual(actualError.code, expectedError.code)
    }
    
    func test_getDogs_givenHttpStatusError_dispatchesToResponseQueue(){
        verifyGetDogsDispatchToMain(data: nil, statusCode: 500, error: nil)
    }
    
    func test_getDogs_giveError_dispatchToResponseQueue(){
        let error = NSError.init(domain: "com.DogPatch", code: -100, userInfo: nil)
        verifyGetDogsDispatchToMain(data: nil, statusCode: 200, error: error)
    }
    
    fileprivate func verifyGetDogsDispatchToMain(data: Data? = nil, statusCode: Int = 200, error: Error? = nil, line: UInt = #line){
        mockSession.givenDispatchQueue()
        sut = DogPatchClient.init(baseURL: baseURL, session: mockSession, responseQueue: .main)
        let expectation = self.expectation(description: "Completion wasn't called")
        var thread: Thread!
        let mockTask = sut.gotDogs { _, _ in
            thread = Thread.current
            expectation.fulfill()
            } as! MockURLSessionTask
        let response = HTTPURLResponse.init(url: getDogsURL(), statusCode: statusCode, httpVersion: nil, headerFields: nil)
        mockTask.completionHandler(data, response, error)
        waitForExpectations(timeout: 0.2) { _ in
            XCTAssertTrue(thread.isMainThread)
        }
    }

}
