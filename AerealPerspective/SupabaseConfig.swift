//
//  SupabaseConfig.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//
import Foundation
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://zjopgbnppicnaotsywwl.supabase.co")!,
    supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inpqb3BnYm5wcGljbmFvdHN5d3dsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxMTY2NDcsImV4cCI6MjA5NDY5MjY0N30.cqqTbLXau6Op5A6Gv9r8PinWiqhPF492wOmBqziGM3w"
)
