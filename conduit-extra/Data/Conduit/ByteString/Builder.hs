{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE RankNTypes #-}
-- | Convert a stream of blaze-builder @Builder@s into a stream of @ByteString@s.
--
-- Works with both blaze-builder < 0.4's @Builder@s and
-- 'Data.ByteString.Builder.Builder'.
--
-- Adapted from blaze-builder-enumerator, written by myself and Simon Meier.
--
-- Note that the functions here can work in any monad built on top of @IO@ or
-- @ST@.
--
-- Since 1.1.7.0
--
module Data.Conduit.ByteString.Builder
    (

  -- * Conduits from builders to bytestrings
    builderToByteString
  , unsafeBuilderToByteString
  , builderToByteStringWith

  -- ** Flush
  , builderToByteStringFlush
  , builderToByteStringWithFlush

  -- * Buffers
  , Buffer

  -- ** Status information
  , freeSize
  , sliceSize
  , bufferSize

  -- ** Creation and modification
  , allocBuffer
  , reuseBuffer
  , nextSlice

  -- ** Conversion to bytestings
  , unsafeFreezeBuffer
  , unsafeFreezeNonEmptyBuffer

  -- * Buffer allocation strategies
  , BufferAllocStrategy
  , allNewBuffersStrategy
  , reuseBufferStrategy
    ) where

import Data.Conduit
import Control.Monad (unless, liftM)
import Control.Monad.Trans.Class (lift, MonadTrans)

import qualified Data.ByteString                   as S

import Control.Monad.Primitive (PrimMonad, unsafePrimToPrim)
import Control.Monad.Base (MonadBase, liftBase)
import Data.Streaming.ByteString.Builder.Class

unsafeLiftIO :: (MonadBase base m, PrimMonad base) => IO a -> m a
unsafeLiftIO = liftBase . unsafePrimToPrim

-- | Incrementally execute builders and pass on the filled chunks as
-- bytestrings.
builderToByteString :: (MonadBase base m, PrimMonad base, StreamingBuilder b)
                    => Conduit b m S.ByteString
builderToByteString =
  builderToByteStringWith defaultStrategy
{-# INLINE builderToByteString #-}

-- |
--
-- Since 0.0.2
builderToByteStringFlush :: (MonadBase base m, PrimMonad base, StreamingBuilder b)
                         => Conduit (Flush b) m (Flush S.ByteString)
builderToByteStringFlush =
  builderToByteStringWithFlush defaultStrategy
{-# INLINE builderToByteStringFlush #-}

-- | Incrementally execute builders on the given buffer and pass on the filled
-- chunks as bytestrings. Note that, if the given buffer is too small for the
-- execution of a build step, a larger one will be allocated.
--
-- WARNING: This conduit yields bytestrings that are NOT
-- referentially transparent. Their content will be overwritten as soon
-- as control is returned from the inner sink!
unsafeBuilderToByteString :: (MonadBase base m, PrimMonad base, StreamingBuilder b)
                          => IO Buffer  -- action yielding the inital buffer.
                          -> Conduit b m S.ByteString
unsafeBuilderToByteString = builderToByteStringWith . reuseBufferStrategy
{-# INLINE unsafeBuilderToByteString #-}


-- | A conduit that incrementally executes builders and passes on the
-- filled chunks as bytestrings to an inner sink.
--
-- INV: All bytestrings passed to the inner sink are non-empty.
builderToByteStringWith :: (MonadBase base m, PrimMonad base, StreamingBuilder b)
                        => BufferAllocStrategy
                        -> Conduit b m S.ByteString
builderToByteStringWith =
    helper (liftM (fmap Chunk) await) yield'
  where
    yield' Flush = return ()
    yield' (Chunk bs) = yield bs
{-# INLINE builderToByteStringWith #-}

-- |
--
-- Since 0.0.2
builderToByteStringWithFlush
    :: (MonadBase base m, PrimMonad base, StreamingBuilder b)
    => BufferAllocStrategy
    -> Conduit (Flush b) m (Flush S.ByteString)
builderToByteStringWithFlush = helper await yield
{-# INLINE builderToByteStringWithFlush #-}

helper :: (MonadBase base m, PrimMonad base, Monad (t m), MonadTrans t, StreamingBuilder b)
       => t m (Maybe (Flush b))
       -> (Flush S.ByteString -> t m ())
       -> BufferAllocStrategy
       -> t m ()
helper await' yield' strat = do
    (recv, finish) <- lift $ unsafeLiftIO $ newBuilderRecv strat
    let loop = await' >>= maybe finish' cont
        finish' = do
            mbs <- lift $ unsafeLiftIO finish
            maybe (return ()) (yield' . Chunk) mbs
        cont fbuilder = do
            let builder =
                    case fbuilder of
                        Flush -> builderFlush
                        Chunk b -> b
            popper <- lift $ unsafeLiftIO $ recv builder
            let cont' = do
                    bs <- lift $ unsafeLiftIO popper
                    unless (S.null bs) $ do
                        yield' (Chunk bs)
                        cont'
            cont'
            case fbuilder of
                Flush -> yield' Flush
                Chunk _ -> return ()
            loop
    loop
{-# INLINE helper #-}
