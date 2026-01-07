//
//  instant.schema.swift
//  instantdb-example
//

import InstantDB

let schema = InstantSchema {
  Entity("profiles")
    .field("username", .string, .unique, .indexed)
    .field("displayName", .string)
    .optionalField("bio", .string)
    .optionalField("avatarUrl", .string)
    .field("createdAt", .date)
  
  Entity("posts")
    .field("content", .string)
    .optionalField("imageUrl", .string)
    .field("createdAt", .date, .indexed)
  
  Entity("comments")
    .field("text", .string)
    .field("createdAt", .date)
  
  Entity("messages")
    .field("text", .string)
    .field("createdAt", .date, .indexed)
    .field("isRead", .boolean)
  
  Entity("friendships")
    .field("status", .string, .indexed)
    .field("createdAt", .date)
  
  Link("profiles", "posts")
    .hasMany()
    .to("posts", "author")
  
  Link("profiles", "comments")
    .hasMany()
    .to("comments", "author")
  
  Link("posts", "comments")
    .hasMany()
    .to("comments", "post")
  
  Link("profiles", "sentMessages")
    .hasMany()
    .to("messages", "sender")
  
  Link("profiles", "receivedMessages")
    .hasMany()
    .to("messages", "recipient")
  
  Link("profiles", "friendshipsInitiated")
    .hasMany()
    .to("friendships", "requester")
  
  Link("profiles", "friendshipsReceived")
    .hasMany()
    .to("friendships", "addressee")
}
