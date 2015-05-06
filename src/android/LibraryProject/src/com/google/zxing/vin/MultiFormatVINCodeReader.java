package com.google.zxing.vin;

import com.google.zxing.DecodeHintType;
import com.google.zxing.FormatException;
import com.google.zxing.NotFoundException;
import com.google.zxing.Reader;
import com.google.zxing.ReaderException;
import com.google.zxing.Result;
import com.google.zxing.common.BitArray;
import com.google.zxing.oned.Code128Reader;
import com.google.zxing.oned.Code39Reader;
import com.google.zxing.oned.OneDReader;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Map;


public class MultiFormatVINCodeReader extends OneDReader {

    private final OneDReader[] readers;

    public MultiFormatVINCodeReader(Map<DecodeHintType, ?> hints) {
        boolean useCode39CheckDigit = hints != null &&
                hints.get(DecodeHintType.ASSUME_CODE_39_CHECK_DIGIT) != null;
        Collection<OneDReader> readers = new ArrayList<OneDReader>();

        readers.add(new Code39Reader(useCode39CheckDigit));
        readers.add(new Code128Reader());

        this.readers = readers.toArray(new OneDReader[readers.size()]);
    }

    @Override
    public Result decodeRow(int rowNumber,
                            BitArray row,
                            Map<DecodeHintType, ?> hints) throws NotFoundException {
        for (OneDReader reader : readers) {
            try {
                Result result = reader.decodeRow(rowNumber, row, hints);
                result = verifyVIN(result);
                if (result != null) {
                    return result;
                }
            } catch (ReaderException re) {
                // continue
            }
        }

        throw NotFoundException.getNotFoundInstance();
    }

    private Result verifyVIN(Result result) throws FormatException {
        String text = result.getText();
        if (text != null && text.length() >= 17) {
            if (text.length() == 18 && text.charAt(0) == 'I') {
                // strip 'I' in the VIN code
                text = text.substring(1);
                result = new Result(text, result.getRawBytes(),
                        result.getResultPoints(), result.getBarcodeFormat(),
                        result.getTimestamp());
            }
            VIN.validateVIN(text);
            return result;
        }
        return null;
    }

    @Override
    public void reset() {
        for (Reader reader : readers) {
            reader.reset();
        }
    }
}
