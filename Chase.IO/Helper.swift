//
//  Helper.swift
//  Chase.IO
//
//  Created by 谢行健 on 05/02/2023.
//

import Foundation

struct Respond: Decodable {
    let users: [User]
}

struct User: Decodable {
    let user_id: UUID
}

func userIdFromRefId(refID: UUID) -> UUID {
    let headers = [
      "accept": "application/json",
      "dev-id": DEVID,
      "x-api-key": XAPIKEY
    ]

    let request = NSMutableURLRequest(url: NSURL(string: "https://api.tryterra.co/v2/userInfo?reference_id=\(refID.uuidString)")! as URL,
                                            cachePolicy: .useProtocolCachePolicy,
                                        timeoutInterval: 10.0)
    request.httpMethod = "GET"
    request.allHTTPHeaderFields = headers

    let session = URLSession.shared
    let group = DispatchGroup()
    let queue = DispatchQueue(label: "helper.Terra")
    var res: Respond? = nil
    let dataTask = session.dataTask(with: request as URLRequest, completionHandler: { (data, response, error) -> Void in
      if (error != nil) {
        print(error as Any)
      } else {
          print(String(data: data!, encoding: .utf8))
          res = try! JSONDecoder().decode(Respond.self, from: data!)
        group.leave()
      }
    })
    
    group.enter()
    queue.async(group:group) {
        dataTask.resume()
    }
    group.wait()
    return res!.users[0].user_id
}
