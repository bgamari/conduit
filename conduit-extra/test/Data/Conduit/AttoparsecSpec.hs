{-# LANGUAGE CPP               #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections     #-}
{-# OPTIONS_GHC -fno-warn-incomplete-patterns #-}
module Data.Conduit.AttoparsecSpec (spec) where
import           Control.Exception                (fromException)
import           Test.Hspec

import           Control.Applicative              ((<*), (<|>))
import           Control.Monad
import           Control.Monad.Trans.Resource (runExceptionT)
import qualified Data.Attoparsec.ByteString.Char8
import qualified Data.Attoparsec.Text
import           Data.Conduit
import           Data.Conduit.Attoparsec
import qualified Data.Conduit.List                as CL

spec :: Spec
spec = describe "Data.Conduit.AttoparsecSpec" $ do
    describe "error position" $ do
        it "works for text" $ do
            let input = ["aaa\na", "aaa\n\n", "aaa", "aab\n\naaaa"]
                badLine = 4
                badCol = 6
                parser = Data.Attoparsec.Text.endOfInput <|> (Data.Attoparsec.Text.notChar 'b' >> parser)
                sink = sinkParser parser
                sink' = sinkParserEither parser
            ea <- runExceptionT $ CL.sourceList input $$ sink
            case ea of
                Left e ->
                    case fromException e of
                        Just pe -> do
                            errorPosition pe `shouldBe` Position badLine badCol
            ea' <- CL.sourceList input $$ sink'
            case ea' of
                Left pe ->
                    errorPosition pe `shouldBe` Position badLine badCol
        it "works for bytestring" $ do
            let input = ["aaa\na", "aaa\n\n", "aaa", "aab\n\naaaa"]
                badLine = 4
                badCol = 6
                parser = Data.Attoparsec.ByteString.Char8.endOfInput <|> (Data.Attoparsec.ByteString.Char8.notChar 'b' >> parser)
                sink = sinkParser parser
                sink' = sinkParserEither parser
            ea <- runExceptionT $ CL.sourceList input $$ sink
            case ea of
                Left e ->
                    case fromException e of
                        Just pe -> do
                            errorPosition pe `shouldBe` Position badLine badCol
            ea' <- CL.sourceList input $$ sink'
            case ea' of
                Left pe ->
                    errorPosition pe `shouldBe` Position badLine badCol
        it "works in last chunk" $ do
            let input = ["aaa\na", "aaa\n\n", "aaa", "aab\n\naaaa"]
                badLine = 6
                badCol = 5
                parser = Data.Attoparsec.Text.char 'c' <|> (Data.Attoparsec.Text.anyChar >> parser)
                sink = sinkParser parser
                sink' = sinkParserEither parser
            ea <- runExceptionT $ CL.sourceList input $$ sink
            case ea of
                Left e ->
                    case fromException e of
                        Just pe -> do
                            errorPosition pe `shouldBe` Position badLine badCol
            ea' <- CL.sourceList input $$ sink'
            case ea' of
                Left pe ->
                    errorPosition pe `shouldBe` Position badLine badCol
        it "works in last chunk" $ do
            let input = ["aaa\na", "aaa\n\n", "aaa", "aa\n\naaaab"]
                badLine = 6
                badCol = 6
                parser = Data.Attoparsec.Text.string "bc" <|> (Data.Attoparsec.Text.anyChar >> parser)
                sink = sinkParser parser
                sink' = sinkParserEither parser
            ea <- runExceptionT $ CL.sourceList input $$ sink
            case ea of
                Left e ->
                    case fromException e of
                        Just pe -> do
                            errorPosition pe `shouldBe` Position badLine badCol
            ea' <- CL.sourceList input $$ sink'
            case ea' of
                Left pe ->
                    errorPosition pe `shouldBe` Position badLine badCol
        it "works after new line in text" $ do
            let input = ["aaa\n", "aaa\n\n", "aaa", "aa\nb\naaaa"]
                badLine = 5
                badCol = 1
                parser = Data.Attoparsec.Text.endOfInput <|> (Data.Attoparsec.Text.notChar 'b' >> parser)
                sink = sinkParser parser
                sink' = sinkParserEither parser
            ea <- runExceptionT $ CL.sourceList input $$ sink
            case ea of
                Left e ->
                    case fromException e of
                        Just pe -> do
                            errorPosition pe `shouldBe` Position badLine badCol
            ea' <- CL.sourceList input $$ sink'
            case ea' of
                Left pe ->
                    errorPosition pe `shouldBe` Position badLine badCol
        it "works after new line in bytestring" $ do
            let input = ["aaa\n", "aaa\n\n", "aaa", "aa\nb\naaaa"]
                badLine = 5
                badCol = 1
                parser = Data.Attoparsec.ByteString.Char8.endOfInput <|> (Data.Attoparsec.ByteString.Char8.notChar 'b' >> parser)
                sink = sinkParser parser
                sink' = sinkParserEither parser
            ea <- runExceptionT $ CL.sourceList input $$ sink
            case ea of
                Left e ->
                    case fromException e of
                        Just pe -> do
                            errorPosition pe `shouldBe` Position badLine badCol
            ea' <- CL.sourceList input $$ sink'
            case ea' of
                Left pe ->
                    errorPosition pe `shouldBe` Position badLine badCol
        it "works for first line" $ do
            let input = ["aab\na", "aaa\n\n", "aaa", "aab\n\naaaa"]
                badLine = 1
                badCol = 3
                parser = Data.Attoparsec.Text.endOfInput <|> (Data.Attoparsec.Text.notChar 'b' >> parser)
                sink = sinkParser parser
                sink' = sinkParserEither parser
            ea <- runExceptionT $ CL.sourceList input $$ sink
            case ea of
                Left e ->
                    case fromException e of
                        Just pe -> do
                            errorPosition pe `shouldBe` Position badLine badCol
            ea' <- CL.sourceList input $$ sink'
            case ea' of
                Left pe ->
                    errorPosition pe `shouldBe` Position badLine badCol

    describe "conduitParser" $ do
        it "parses a repeated stream" $ do
            let input = ["aaa\n", "aaa\naaa\n", "aaa\n"]
                parser = Data.Attoparsec.Text.string "aaa" <* Data.Attoparsec.Text.endOfLine
                sink = conduitParserEither parser =$= CL.consume
            (Right ea) <- runExceptionT $ CL.sourceList input $$ sink
            let chk a = case a of
                          Left{} -> False
                          Right (_, xs) -> xs == "aaa"
                chkp l = (PositionRange (Position l 1) (Position (l+1) 1))
            forM_ ea $ \ a -> a `shouldSatisfy` chk :: Expectation
            forM_ (zip ea [1..]) $ \ (Right (pos, _), l) -> pos `shouldBe` chkp l
            length ea `shouldBe` 4

        it "positions on first line" $ do
            results <- yield "hihihi\nhihi"
                $$ conduitParser (Data.Attoparsec.Text.string "\n" <|> Data.Attoparsec.Text.string "hi")
                =$ CL.consume
            let f (a, b, c, d, e) = (PositionRange (Position a b) (Position c d), e)
            results `shouldBe` map f
                [ (1, 1, 1, 3, "hi")
                , (1, 3, 1, 5, "hi")
                , (1, 5, 1, 7, "hi")

                , (1, 7, 2, 1, "\n")

                , (2, 1, 2, 3, "hi")
                , (2, 3, 2, 5, "hi")
                ]
