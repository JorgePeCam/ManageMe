import Foundation
import Accelerate

struct VectorMath {
    static func cosineSimilarity(_ queryVector: [Float], _ dbVector: [Float]) -> Float {
        // Validación básica
        guard queryVector.count == dbVector.count else { return 0.0 }
        
        // Usamos SIMD (instrucciones de bajo nivel) para velocidad extrema
        let count = vDSP_Length(queryVector.count)
        
        // 1. Producto Punto (Dot Product)
        var dotProduct: Float = 0.0
        vDSP_dotpr(queryVector, 1, dbVector, 1, &dotProduct, count)
        
        // 2. Magnitudes (Norma Euclídea)
        var queryMag: Float = 0.0
        vDSP_svesq(queryVector, 1, &queryMag, count) // Suma de cuadrados
        queryMag = sqrt(queryMag)
        
        var dbMag: Float = 0.0
        vDSP_svesq(dbVector, 1, &dbMag, count)
        dbMag = sqrt(dbMag)
        
        // Evitar división por cero
        if queryMag == 0 || dbMag == 0 { return 0.0 }
        
        return dotProduct / (queryMag * dbMag)
    }
}
