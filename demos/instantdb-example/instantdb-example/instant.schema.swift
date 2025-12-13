//
//  insant.swift
//  instantdb-example
//
//  Created by Tornike Gomareli on 09.12.25.
//

import InstantDB

let schema = InstantSchema {
  Entity(Goal.self) {
    Attr(\Goal.title).indexed().optional()
    Attr(\Goal.difficulty).optional()
    Attr(\Goal.completed).optional()
  }
  
  Entity(User.self) {
    Attr(\User.email).indexed().unique()
    Attr(\User.name)
  }
  
  Link(from: User.self, "goals")
    .hasMany()
    .to(Goal.self, "owner")
}
